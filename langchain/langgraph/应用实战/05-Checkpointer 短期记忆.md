# 应用实战 05：客服会话记住上下文

> 对应：[课 5 Checkpointer 短期记忆](../stages/2-执行模型与状态持久化/lessons/05-Checkpointer%20短期记忆.md)
> 覆盖知识点：checkpoint 与 thread_id / checkpointer 后端选型 / 断点续跑与状态恢复
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行；SQLite 项另装 `langgraph-checkpoint-sqlite`）
> ✅ TypeScript 侧实测于 `playground-ts/`（`@langchain/langgraph` 1.5.1 / Node 22，`npm run a05`；SQLite 项另装 `@langchain/langgraph-checkpoint-sqlite` 1.1.0）

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

::: code-group
```python [Python]
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

```typescript [TypeScript]
import { Annotation, END, MemorySaver, START, StateGraph } from "@langchain/langgraph";

const State = Annotation.Root({
  question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  // 累加：每句话都留下（等价于 Python 的 Annotated[list[str], add]）
  history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const record = (s: typeof State.State) => ({ history: [s.question] });

const answer = (s: typeof State.State) => {
  const n = s.history.length;
  return { answer: `已收到你的 ${n} 条消息，最新一条是：${s.history[n - 1]}` };
};

const builder = new StateGraph(State)
  .addNode("record", record)
  // ⚠️ 节点名不能与状态字段同名（课 3 已记录），所以叫 reply 而不是 answer
  .addNode("reply", answer)
  .addEdge(START, "record")
  .addEdge("record", "reply")
  .addEdge("reply", END);

// ⚠️ TS 是 MemorySaver（Python 是 InMemorySaver），且 compile 收对象参数
const graph = builder.compile({ checkpointer: new MemorySaver() });
const cfg = { configurable: { thread_id: "user-001" } };

for (const q of ["我的订单还没发货", "那能退款吗", "算了，发货就行"]) {
  const r = await graph.invoke({ question: q, history: [], answer: "" }, cfg);
  console.log(`  问：${q}`);
  console.log(`  答：${r.answer}`);
}
```
:::

实测输出：

实测输出（Python）：

```
  问：我的订单还没发货
  答：已收到你的 1 条消息，最新一条是：我的订单还没发货
  问：那能退款吗
  答：已收到你的 2 条消息，最新一条是：那能退款吗
  问：算了，发货就行
  答：已收到你的 3 条消息，最新一条是：算了，发货就行
```

实测输出（TypeScript，`npm run a05`）：

```
  问：我的订单还没发货
  答：已收到你的 1 条消息，最新一条是：我的订单还没发货
  问：那能退款吗
  答：已收到你的 2 条消息，最新一条是：那能退款吗
  问：算了，发货就行
  答：已收到你的 3 条消息，最新一条是：算了，发货就行
```

> ✅ **记住了**。关键点只有两个：`compile(checkpointer=...)`，以及每次都传**同一个** `thread_id`。

> 💡 TS 侧三处必改：①类名是 `MemorySaver`（Python 是 `InMemorySaver`）；②`compile` 收**对象参数** `{ checkpointer }`，不是关键字参数；③节点名从 `answer` 改成 `reply`——**节点名不能与状态字段同名**，否则 `addNode` 当场抛 `answer is already being used as a state attribute`（课 3 已记录）。`configurable` 里的键名 `thread_id` 两侧一致，仍是下划线。

---

## 第 2 跳：多用户不串台 + 崩了不重来（问题）

### 多用户隔离

::: code-group
```python [Python]
for user, qs in [("user-001", ["我是张三"]), ("user-002", ["我是李四"])]:
    cfg_u = {"configurable": {"thread_id": user}}
    r = graph.invoke({"question": qs[0], "history": [], "answer": ""}, cfg_u)
    print(f"  {user}: {r['history']}")
```

```typescript [TypeScript]
for (const [user, q] of [
  ["user-001", "我是张三"],
  ["user-002", "我是李四"],
] as const) {
  const r = await graph.invoke(
    { question: q, history: [], answer: "" },
    { configurable: { thread_id: user } }
  );
  console.log(`  ${user}:`, r.history);
}
```
:::

实测：

实测（Python）：

```
  user-001: ['我的订单还没发货', '那能退款吗', '算了，发货就行', '我是张三']
  user-002: ['我是李四']
```

实测（TypeScript）：

```
  user-001: [ '我的订单还没发货', '那能退款吗', '算了，发货就行', '我是张三' ]
  user-002: [ '我是李四' ]
```

> ✅ **互不干扰**——`user-002` 的 history 里完全没有张三说过的话。

> 💡 内容逐字相同，只有数组打印格式差异：Python 用 `'...'`，TS 用 `'...'` 但**方括号内侧多空格**（`[ 'A' ]`）。

### 崩了接着跑

模拟"回答节点崩了"：

::: code-group
```python [Python]
def answer_flaky(state: State) -> dict:
    if len(state["history"]) >= 3:      # 攒够 3 条就"崩"
        raise RuntimeError("下游服务超时")
    return {"answer": f"已收到 {len(state['history'])} 条"}
```

```typescript [TypeScript]
const answerFlaky = (s: typeof State.State) => {
  if (s.history.length >= 3) throw new Error("下游服务超时"); // 攒够 3 条就"崩"
  return { answer: `已收到 ${s.history.length} 条` };
};
```
:::

崩溃后看看存档里剩下什么，再修好重跑：

::: code-group
```python [Python]
st = graph.get_state(cfg)
print("  崩溃后 values:", st.values)
print("  崩溃后 next:  ", st.next)

# 修好之后，传 None 表示"沿用现有状态继续"
r = graph.invoke(None, cfg)
print("  续跑结果:", r)
```

```typescript [TypeScript]
const st = await graph.getState(cfg);
console.log("  崩溃后 values:", st.values);
console.log("  崩溃后 next:  ", st.next);

// 修好之后，传 null 表示"沿用现有状态继续"
const r = await graph.invoke(null, cfg);
console.log("  续跑结果:", r);
```
:::

实测：

实测（Python）：

```
  崩了: RuntimeError: 下游服务超时
  崩溃后 history: ['我的订单还没发货', '那能退款吗', '算了，发货就行']
  崩溃后 next:    ('answer',)
  续跑结果 history: ['我的订单还没发货', '那能退款吗', '算了，发货就行']
  续跑结果 answer:  已收到 3 条消息，最新一条是：算了，发货就行
```

实测（TypeScript）：

```
  崩了: Error: 下游服务超时
  崩溃后 history: [ '我的订单还没发货', '那能退款吗', '算了，发货就行' ]
  崩溃后 next:   [ 'reply' ]
  续跑结果 history: [ '我的订单还没发货', '那能退款吗', '算了，发货就行' ]
  续跑结果 answer:  已收到你的 3 条消息，最新一条是：算了，发货就行
```

> ✅ **`history` 一条没丢**，重跑只补了崩掉的 `answer` 那一步。

> 💡 TS 侧这一跳有两个实操差异：①`st.next` 是**数组** `['reply']`，Python 是**元组** `('answer',)`；②崩溃后要续跑，必须让「修好的图」和「崩掉的图」**共用同一个 saver 实例**——Python 里可以原地改节点实现，TS 的图编译后不可变，只能重新 `compile` 并把同一个 `checkpointer` 传进去，否则新 saver 是空的、`next` 也是空，续跑等于从头开始。`invoke(null, cfg)` 的写法两侧一致。

> ⚠️ **注意一个反直觉的点**：崩溃后 `history` 里**已经**有"算了，发货就行"了——因为 `record` 那一步已经跑完落盘，崩的是后面的 `answer`。**存档点是按批切的，不是按"你这一轮是否成功"切的。**

---

## 第 3 跳：换 SQLite，让记忆活过重启（综合）

内存版进程一退就没。换成 `SqliteSaver`：

::: code-group
```python [Python]
from langgraph.checkpoint.sqlite import SqliteSaver

DB = "./customer-service.sqlite"

with SqliteSaver.from_conn_string(DB) as saver:
    graph = b.compile(checkpointer=saver)
    cfg = {"configurable": {"thread_id": "user-001"}}
    graph.invoke({"question": "我的订单还没发货", ...}, cfg)
    print(graph.get_state(cfg).values["history"])
```

```typescript [TypeScript]
import { SqliteSaver } from "@langchain/langgraph-checkpoint-sqlite";

const DB = "./customer-service.sqlite";

// TS 侧 fromConnString 直接返回实例（Python 是上下文管理器）
const graph = builder.compile({ checkpointer: SqliteSaver.fromConnString(DB) });
const cfg = { configurable: { thread_id: "user-001" } };
await graph.invoke({ question: "我的订单还没发货", history: [], answer: "" }, cfg);
console.log((await graph.getState(cfg)).values.history);
```
:::

**用两个独立连接先后打开同一个 db 文件**，实测：

实测（Python）：

```
进程内连跑两次: ['我的订单还没发货', '那能退款吗']
换个连接再读:   ['我的订单还没发货', '那能退款吗']
表: ['checkpoints', 'writes']
```

实测（TypeScript）：

```
  进程内连跑两次: [ '我的订单还没发货', '那能退款吗' ]
  换个连接再读:   [ '我的订单还没发货', '那能退款吗' ]
```

> ✅ **换个连接读，上次的还在。**

> 💡 TS 侧两处差异：①包名是 `@langchain/langgraph-checkpoint-sqlite`，`SqliteSaver.fromConnString(db)` **直接返回实例**（Python 的 `from_conn_string` 是上下文管理器，要 `with`）；②本脚本把 db 建在 `mkdtemp` 临时目录并跑完清理，所以没有打印「表: [...]」那一行——想看表名请自行用 `sqlite3` 打开文件。

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

::: code-group
```python [Python]
cfg = {"configurable": {"thread_id": "t1"}}
print(graph.invoke({"question": "A", "history": [], "answer": ""}, cfg)["history"])
# 第二次我传了一份"新起点"
print(graph.invoke({"question": "B", "history": ["新起点"], "answer": ""}, cfg)["history"])
```

```typescript [TypeScript]
const cfg = { configurable: { thread_id: "t1" } };
console.log((await graph.invoke({ question: "A", history: [], answer: "" }, cfg)).history);

// 第二次我传了一份"新起点"
console.log(
  (await graph.invoke({ question: "B", history: ["新起点"], answer: "" }, cfg)).history
);
```
:::

实测（Python）：

```
['A']
['A', '新起点', 'B']          # 不是 ['B']，也不是 ['新起点','B']
```

实测（TypeScript）：

```
  第1次:           [ 'A' ]
  第2次(传新起点):  [ 'A', '新起点', 'B' ]
```

> ⚠️ **你传的 `history` 没有被当成"新起点"，而是被 `operator.add` 合并进了历史**——所以变成了 3 项。TS 侧的 `concat` reducer 语义完全相同。

**想真正从头开始** → 换 `thread_id`：

::: code-group
```python [Python]
import uuid
cfg_new = {"configurable": {"thread_id": str(uuid.uuid4())}}
```

```typescript [TypeScript]
import { randomUUID } from "node:crypto";

const cfgNew = { configurable: { thread_id: randomUUID() } };
```
:::

实测（`str(uuid.uuid4())` 作新编号）：

实测（Python）：

```
  第1次:            ['A']
  第2次(传新起点):   ['A', '新起点', 'B']
  换新编号:         ['新起点', 'B']
```

实测（TypeScript）：

```
  第1次:           [ 'A' ]
  第2次(传新起点):  [ 'A', '新起点', 'B' ]
  换新编号:        [ '新起点', 'B' ]
```

> ✅ 干净的新会话——只有你这次传的内容。TS 侧用 `randomUUID()`（`node:crypto`）生成新编号，等价于 Python 的 `str(uuid.uuid4())`。

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
3. **SQLite 需要额外装包**（Python：`langgraph-checkpoint-sqlite`；TS：`@langchain/langgraph-checkpoint-sqlite`），且它是**单机**方案，多副本部署请上 Postgres。

### TS 侧写法对照

| 项 | Python | TypeScript |
|:--|--------|-----------|
| 内存 checkpointer | `InMemorySaver()`（`langgraph.checkpoint.memory`） | `new MemorySaver()`（`@langchain/langgraph`） |
| 编译传参 | `compile(checkpointer=saver)` | `compile({ checkpointer: saver })`（对象） |
| SQLite 构造 | `SqliteSaver.from_conn_string(db)`（上下文管理器） | `SqliteSaver.fromConnString(db)`（直接返回实例） |
| 崩溃后 `next` | 元组 `('answer',)` | 数组 `['reply']` |
| 续跑 | `graph.invoke(None, cfg)` | `graph.invoke(null, cfg)` |
| 读快照 | `graph.get_state(cfg)` | `await graph.getState(cfg)` |
| 新会话编号 | `str(uuid.uuid4())` | `randomUUID()`（`node:crypto`） |
