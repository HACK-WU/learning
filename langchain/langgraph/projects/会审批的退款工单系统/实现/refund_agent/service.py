"""退款工单的服务封装层。

职责：把"业务参数"和"LangGraph 的运行参数"隔开。

知识点回指：
- 阶段 2 · 课 5「thread_id」——一次工单一个 thread，天然隔离
- 阶段 2 · 课 7「Streaming」——对外暴露流式接口（SSE 的数据源）
- 阶段 3 · 课 9「Time-travel」——暴露回放与分叉
- 阶段 4 · 课 13「SSE」——这里的 stream() 就是 /runs/stream 的本地版
"""
from __future__ import annotations

from typing import Iterator

from langchain_core.runnables import RunnableConfig
from langgraph.types import Command

from .deps import CONFIG_KEY, Deps
from .graph import build_graph
from .state import RefundState, empty_state


class RefundService:
    """退款工单服务：一次实例化 = 一套依赖 + 一个 checkpointer。"""

    def __init__(self, deps: Deps | None = None, checkpointer=None, store=None):
        self.deps = deps or Deps.fake()
        self.graph = build_graph(checkpointer=checkpointer, store=store)

    def _config(self, thread_id: str) -> RunnableConfig:
        """组装 config：thread_id 管隔离，deps 管依赖注入。

        知识点回指：阶段 4 · 课 12 实测 —— 依赖必须走 configurable，不能塞 State
        """
        return {
            "configurable": {
                "thread_id": thread_id,
                CONFIG_KEY: self.deps,
            }
        }

    # ---------------- 提交工单 ----------------
    def submit(
        self,
        order_id: str,
        amount: float,
        reason: str = "用户申请",
        thread_id: str | None = None,
    ) -> dict:
        """提交一笔退款申请，返回最终状态（可能卡在 interrupt）。"""
        tid = thread_id or f"refund-{order_id}"
        state = empty_state(order_id, amount, reason)
        return self.graph.invoke(state, config=self._config(tid))

    # ---------------- 流式（SSE 的数据源） ----------------
    def stream(
        self,
        order_id: str,
        amount: float,
        reason: str = "用户申请",
        thread_id: str | None = None,
        stream_mode: list[str] | None = None,
    ) -> Iterator:
        """流式执行。

        知识点回指：阶段 2 · 课 7（7 种 stream_mode）+ 阶段 4 · 课 13（SSE）
        - stream_mode=["updates"] 对应 SSE 里的 event: updates
        - 多模式 + subgraphs 时返回**三元组**（课 7 实测）
        """
        tid = thread_id or f"refund-{order_id}"
        state = empty_state(order_id, amount, reason)
        modes = stream_mode or ["updates"]
        return self.graph.stream(
            state, config=self._config(tid), stream_mode=modes
        )

    # ---------------- 人工审批（Resume） ----------------
    def approve(self, thread_id: str, approved: bool) -> dict:
        """审批并恢复执行。

        知识点回指：阶段 3 · 课 8
        - Command(resume=...) 会把值交回 interrupt() 的返回值
        - 恢复时 human_approve 整个节点**重跑**（所以不能有副作用）
        - ⚠️ 实测坑：resume=None 会撞 langgraph 自身 bug（课 8 验证六）
        """
        return self.graph.invoke(
            Command(resume=approved), config=self._config(thread_id)
        )

    # ---------------- 查看 / 回放 ----------------
    def get_state(self, thread_id: str):
        """看当前状态（含是否卡在 interrupt）。"""
        return self.graph.get_state(self._config(thread_id))

    def history(self, thread_id: str):
        """列出全部存档点 —— time-travel 的原料。

        知识点回指：阶段 3 · 课 9
        """
        return list(self.graph.get_state_history(self._config(thread_id)))

    def replay_from(self, thread_id: str, checkpoint_id: str, patch: dict | None = None):
        """从某个存档点分叉重跑。

        知识点回指：阶段 3 · 课 9 实测教训：
        - 跨 thread 分叉**状态带不过去**（会 KeyError），所以本方法固定同 thread
        - 改"结论"（decision）会被下游重算覆盖，要改就改**最上游的依据**（amount）
        """
        cfg = self._config(thread_id)
        if patch:
            self.graph.update_state(cfg, patch)
        return self.graph.invoke(None, config=cfg)
