# 应用实战 05：客服会话记住上下文

> 对应：[课 5 Checkpointer 短期记忆](../stages/2-执行模型与状态持久化/lessons/05-Checkpointer%20短期记忆.md)
> 覆盖知识点：checkpoint 与 thread_id / checkpointer 后端选型 / 断点续跑与状态恢复
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行；SQLite 项另装 `langgraph-checkpoint-sqlite`）

## 场景

做一个客服助手：能记住同一个用户前面说了什么、不同用户互不干扰、跑到一半崩了能接着跑。

三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 单用户连续对话，能记住上文 | checkpoint 与 thread_id |
| 问题 | 多用户不串台 + 崩了不重来 | thread_id 隔离 / 断点续跑 |
| 综合 | 换 SQLite 落盘，跨进程仍在 | checkpointer 后端选型 |

---

## 第 1 跳：让客服记住上文（基础）

最简单的版本：一个节点把用户的话记进历史，另一个节点基于历史回答。

```python
from operator import add
from typing import Annotated

from typing_extensions import TypedDict

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph


class State(TypedDict):
    history: Annotated[list[str], add]   # 累加：每句话都留下
    answer: str


def record(state: State) -> dict:
    return {"history": [state["question"]]}


def answer(state: State) -> dict:
    n = len(state["history"])
    return {"answer": f"已收到你的 {n} 条消息，最新一条是：{state['history'][-1]}"}


b = StateGraph(State)
b.add_node("record", record)
b.add_node("answer", answer)
b.add_edge(START, "record")
b.add_edge("record", "answer")
b.add_edge("answer", END)

graph = b.compile(checkpointer=InMemorySaver())
cfg = {"configurable": {"thread_id": "user-001"}}

for q in ["我的订单还没发货", "那能退款吗", "算了，发货就行"]:
    r = graph.invoke({"question": q, "history": [], "answer": ""}, cfg)
    print(f"  问：{q}")
    print(f"  答：{r['answer']}")
```

实测输出：

```
  问：我的订单还没发货
  答：已收到你的 1 条消息，最新一条是：我的订单还没发货
  问：那能退款吗
  答：已收到你的 2 条消息，最新一条是：那能退款吗
  问：算了，发货就行
  答：已收到你的 3 条消息，最新一条是：算了，发货就行
```

> ✅ **记住了**。关键点只有两个：`compile(checkpointer=...)`，以及每次都传**同一个** `thread_id`。

---

## 第 2 跳：多用户不串台 + 崩了不重来（问题）

### 多用户隔离

```python
for user, qs in [("user-001", ["我是张三"]), ("user-002", ["我是李四"])]:
    cfg_u = {"configurable": {"thread_id": user}}
    r = graph.invoke({"question": qs[0], "history": [], "answer": ""}, cfg_u)
    print(f"  {user}: {r['history']}")
```

实测：

```
  user-001: ['我的订单还没发货', '那能退款吗', '算了，发货就行', '我是张三']
  user-002: ['我是李四']
```

> ✅ **互不干扰**——`user-002` 的 history 里完全没有张三说过的话。

### 崩了接着跑

模拟"回答节点崩了"：

```python
def answer_flaky(state: State) -> dict:
    if len(state["history"]) >= 3:      # 攒够 3 条就"崩"
        raise RuntimeError("下游服务超时")
    return {"answer": f"已收到 {len(state['history'])} 条"}
```

崩溃后看看存档里剩下什么，再修好重跑：

```python
st = graph.get_state(cfg)
print("  崩溃后 values:", st.values)
print("  崩溃后 next:  ", st.next)

# 修好之后，传 None 表示"沿用现有状态继续"
r = graph.invoke(None, cfg)
print("  续跑结果:", r)
```

实测：

```
  崩了: RuntimeError: 下游服务超时
  崩溃后 history: ['我的订单还没发货', '那能退款吗', '算了，发货就行']
  崩溃后 next:    ('answer',)
  续跑结果 history: ['我的订单还没发货', '那能退款吗', '算了，发货就行']
  续跑结果 answer:  已收到 3 条消息，最新一条是：算了，发货就行
```

> ✅ **`history` 一条没丢**，重跑只补了崩掉的 `answer` 那一步。

> ⚠️ **注意一个反直觉的点**：崩溃后 `history` 里**已经**有"算了，发货就行"了——因为 `record` 那一步已经跑完落盘，崩的是后面的 `answer`。**存档点是按批切的，不是按"你这一轮是否成功"切的。**

---

## 第 3 跳：换 SQLite，让记忆活过重启（综合）

内存版进程一退就没。换成 `SqliteSaver`：

```python
from langgraph.checkpoint.sqlite import SqliteSaver

DB = "./customer-service.sqlite"

with SqliteSaver.from_conn_string(DB) as saver:
    graph = b.compile(checkpointer=saver)
    cfg = {"configurable": {"thread_id": "user-001"}}
    graph.invoke({"question": "我的订单还没发货", ...}, cfg)
    print(graph.get_state(cfg).values["history"])
```

**用两个独立连接先后打开同一个 db 文件**，实测：

```
进程内连跑两次: ['我的订单还没发货', '那能退款吗']
换个连接再读:   ['我的订单还没发货', '那能退款吗']
表: ['checkpoints', 'writes']
```

> ✅ **换个连接读，上次的还在。**

而**真正跨进程**（两个独立 OS 进程先后打开同一个文件）的验证，见课 5 正文 4.1 验证四，实测输出：

```
进程 1: ['跑了一次']
进程 2: ['跑了一次', '跑了一次']     # 上次的还在
```

> ⚠️ **需要先装依赖**：`uv run --with langgraph-checkpoint-sqlite`。我第一次跑就是漏了它，报 `ModuleNotFoundError: No module named 'langgraph.checkpoint.sqlite'`。

### 三档后端怎么选

| 场景 | 用哪个 | 实测依据 |
|---|---|---|
| 练手、写单测 | `InMemorySaver` | 换实例读到 `{}` |
| 本地开发 / 单机 | `SqliteSaver` | 跨进程仍在 |
| 线上多实例 | `PostgresSaver` | 需共享存储；注意 `thread_id` 长度限制 |

---

## ⚠️ 最容易踩的坑：以为"再 invoke 一次是重新开始"

这是本课最高发的误解。看实测：

```python
cfg = {"configurable": {"thread_id": "t1"}}
print(graph.invoke({"question": "A", "history": [], "answer": ""}, cfg)["history"])
# 第二次我传了一份"新起点"
print(graph.invoke({"question": "B", "history": ["新起点"], "answer": ""}, cfg)["history"])
```

```
['A']
['A', '新起点', 'B']          # 不是 ['B']，也不是 ['新起点','B']
```

> ⚠️ **你传的 `history` 没有被当成"新起点"，而是被 `operator.add` 合并进了历史**——所以变成了 3 项。

**想真正从头开始** → 换 `thread_id`：

```python
import uuid
cfg_new = {"configurable": {"thread_id": str(uuid.uuid4())}}
```

实测（`str(uuid.uuid4())` 作新编号）：

```
  第1次:            ['A']
  第2次(传新起点):   ['A', '新起点', 'B']
  换新编号:         ['新起点', 'B']
```

> ✅ 干净的新会话——只有你这次传的内容。

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 得到的认识 |
|:--:|---------|-----------|
| 1 | `compile(checkpointer=InMemorySaver())` + 固定 `thread_id` | 同一编号 = 接着上次 |
| 2 | 不同用户不同编号；`invoke(None, cfg)` 续跑 | 编号即隔离边界；崩了只补崩掉那步 |
| 3 | `SqliteSaver.from_conn_string(db)` | 跨进程仍在；两张表对应两种记录 |

**三个提醒**：

1. **`thread_id` 是主键不是标签**——不传直接 `ValueError`。
2. **接着跑是叠加不是覆盖**——带 reducer 的字段会累加上去，想重开请换编号。
3. **SQLite 需要额外装包**（`langgraph-checkpoint-sqlite`），且它是**单机**方案，多副本部署请上 Postgres。
