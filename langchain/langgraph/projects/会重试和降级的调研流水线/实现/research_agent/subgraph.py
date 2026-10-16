"""单个来源的调查子图：会重试、会降级、内部产物不外泄。

知识点回指：
- 阶段 3 · 课 10「节点级超时 / 重试 / 错误处理」
    —— RetryPolicy 配在节点上；默认 retry_on 只重试特定异常
- 阶段 3 · 课 10「子图与状态隔离」
    —— 父子只传共有字段；子图私有字段不泄漏
- 阶段 3 · 课 10「error_handler 兜底不炸图」

🔴 本项目实测出的三个硬事实（langgraph 1.2.11，课里没写）：

1. **`RetryPolicy` 在 `langgraph.types`**，不是 `langgraph.pregel`（后者导入报错）。
2. **默认 `retry_on` 对 `ValueError` 不重试**——实测尝试 1 次就抛。
   所以必须自定义 `retry_on`，否则该重试的不重试、不该重试的白重试。
3. **`error_handler` 只接受 1 个参数，且收到的是「失败节点的 state」，不是异常对象。**
   实测：形参写 `(state, error)` → `TypeError: missing 1 required positional argument`；
   形参写 `(payload)` → 打印出来是 `{'out': []}`（即 state 本身）。
   源码 `pregel/_algo.py:prepare_node_error_handler_task` 也印证：
   它拿的是 `failed_task.input`，`failed_error` 只用于内部判断，**不传给 handler**。

   👉 推论：**想记录错误信息，只能在节点内部 try/except 自己存**。
   本项目的 `fetch` 就是这样做的。
"""
from langgraph.graph import END, START, StateGraph
from langgraph.types import RetryPolicy

from .sources import PermanentError, SourceRegistry, TransientError
from .state import SourceState

# 只重试"值得重试"的：网络抖动类
# ❌ 不写 retry_on 就用默认策略，PermanentError 也会被重试（白费调用）
RETRY = RetryPolicy(
    max_attempts=4,
    initial_interval=0.01,     # 教学演示，别真等默认 0.5s
    backoff_factor=2.0,
    retry_on=TransientError,
)


def build_source_subgraph(registry: SourceRegistry):
    """构建单个来源的调查子图：fetch（带重试）→ 失败则降级。"""

    def fetch(state: SourceState) -> dict:
        """取数据。

        ⚠️ 因为 error_handler 拿不到异常对象（见模块顶部实测 3），
        这里用类属性把最后一次错误"递出去"，供 degrade 读取。
        这是本项目为了拿到错误信息而采用的工程手段。
        """
        src = registry.get(state["source"])
        try:
            data = src.fetch(state["query"])
        except (TransientError, PermanentError) as e:
            # 存到函数属性上，让 degrade 能读到（error_handler 收不到异常）
            fetch.last_error = e          # type: ignore[attr-defined]
            raise                          # 继续抛，交给重试 / 兜底
        return {
            "result": {
                "source": state["source"],
                "ok": True,
                "data": data,
                "error": "",
                "attempts": 1,
            },
            "scratch": [f"取到 {len(data)} 字符"],
        }

    fetch.last_error = None               # type: ignore[attr-defined]

    def degrade(state: SourceState) -> dict:
        """error_handler：兜底不炸图。

        签名必须是**单参数**（实测：双参数会 TypeError）。
        参数内容是失败节点的 state，**不含异常对象**。

        ⚠️ 实测代价：兜底会**截断流程**——后面的节点不跑了。
        所以降级必须自己把结论写完整。
        """
        err = getattr(fetch, "last_error", None)
        if err is None:
            err_text = "未知错误（error_handler 未收到异常对象）"
            kind = "未知"
        else:
            err_text = f"{type(err).__name__}: {err}"
            kind = "抖动" if isinstance(err, TransientError) else "永久"

        return {
            "result": {
                "source": state["source"],
                "ok": False,
                "data": "",
                "error": err_text,
                "attempts": 0,
            },
            "scratch": [f"降级: {kind}失败"],
        }

    b = StateGraph(SourceState)
    # retry_policy 配在节点上；error_handler 兜底（单参数签名）
    b.add_node("fetch", fetch, retry_policy=RETRY, error_handler=degrade)
    b.add_edge(START, "fetch")
    b.add_edge("fetch", END)
    return b.compile()
