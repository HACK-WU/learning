# 应用实战 11：已有脚本想加暂停和断点续跑，要不要重写成图

> 对应：[课 11 Functional API 与选型](../stages/3-可控性与人在环中/lessons/11-Functional%20API%20%E4%B8%8E%E9%80%89%E5%9E%8B.md)
> 覆盖知识点：@entrypoint / @task 模型 / 两套 API 选型
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）
> ✅ TypeScript 侧实测于 `playground-ts/`（`@langchain/langgraph` 1.5.1 / Node 22，`npm run a11`）

## 场景

你手上有个纯脚本：读数据 → 清洗 → 人工确认 → 写回。现在要加"中途暂停等人"和"崩了能续跑"，同事说"那得重写成 StateGraph 吧？"

三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 用两个装饰器给已有脚本加上 checkpoint | @entrypoint / @task |
| 问题 | 撞上"普通函数 resume 必重跑"和"没有具名状态" | task 持久化语义 / previous |
| 综合 | 全部标 @task + previous 收口，给出选型结论 | 选型判据 / 混用边界 |

> 完整方案还需要：生产环境的 checkpointer 选型（SQLite / Postgres）、幂等性保证（写回重复执行会怎样）、以及任务编排的版本演进管理——**这些都不是本课内容**（课 12/13 部署与工程化时展开）。

---

## 第 1 跳：给已有脚本加两个装饰器（基础）

![第 1 跳：加两个装饰器](./assets/app-step1-functional-api.svg)

> 看图：左右是同一份业务代码，区别只在加了 `@entrypoint` / `@task`——**业务代码一行没动**，就有了存档点和暂停能力。

::: code-group

```python [Python]
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task
from langgraph.types import interrupt

SIDE = {"load": 0, "clean": 0}


@task
def load(src: str) -> list:
    SIDE["load"] += 1
    return [3, 1, 2]


def clean(data: list) -> list:          # ← 注意：这个没加 @task
    SIDE["clean"] += 1
    return sorted(data)


@entrypoint(checkpointer=InMemorySaver())
def process(src: str) -> dict:
    data = load(src).result()
    cleaned = clean(data)
    ok = interrupt({"question": "清洗结果对吗", "data": cleaned})
    return {"data": cleaned, "approved": ok}


cfg = {"configurable": {"thread_id": "job-1"}}
r = process.invoke("orders.csv", config=cfg)
print("invoke ->", r)
print(f"副作用计数: {SIDE}")
```

```typescript [TypeScript]
import { entrypoint, task, interrupt, MemorySaver } from "@langchain/langgraph";

const SIDE = { load: 0, clean: 0 };

// ⚠️ TS 的 task 是 task(name, fn) 工厂，没有装饰器语法
const load = task("load", async (src: string) => {
  SIDE.load += 1;
  return [3, 1, 2];
});

// ← 这个故意不标 task（就是普通函数）
const clean = (data: number[]) => {
  SIDE.clean += 1;
  return [...data].sort((a, b) => a - b);
};

const process = entrypoint(
  { name: "process", checkpointer: new MemorySaver() },
  async (src: string) => {
    const data = await load(src);      // ⚠️ TS 返回 Promise，不是 .result()
    const cleaned = clean(data);
    const ok = interrupt({ question: "清洗结果对吗", data: cleaned });
    return { data: cleaned, approved: ok };
  }
);

const cfg = { configurable: { thread_id: "job-1" } };
const r = await process.invoke("orders.csv", cfg);
console.log("invoke ->", JSON.stringify(r));
console.log(`副作用计数: ${JSON.stringify(SIDE)}`);
```

:::


实测输出：

```
invoke -> {'__interrupt__': [Interrupt(value={'question': '清洗结果对吗', 'data': [1, 2, 3]}, id='...')]}
副作用计数: {'load': 1, 'clean': 1}
```

TypeScript 侧（`npm run a11` 第一段）：

```
不传 config -> Error: Failed to put checkpoint. The passed RunnableConfig is missing a required "thread_id" field in its "configurable" property. When using a che
invoke -> {"__interrupt__":[{"id":"0d708c1d6a68471b2a863afda7573fec","value":{"question":"清洗结果对吗","data":[1,2,3]}}]}
副作用计数: {"load":1,"clean":1}
```

> ✅ **没有 State、没有 `add_node`、没有 `add_edge`**——控制流还是原来那几行，只是多了两个装饰器和一个 `config`。
> ⚠️ **`config` 是必填的**（挂了 checkpointer 时）。不传直接 `ValueError: Checkpointer requires one or more of the following 'configurable' keys: thread_id, checkpoint_ns, checkpoint_id`。

> ⚠️ **TS 侧三处写法差异**：① 没有装饰器——`entrypoint({ name, checkpointer }, fn)` 是**选项对象在前、函数在后**，而且 **`name` 必填**（Python 自动取函数名）；② `task("load", fn)` 也是**名字在前**，调用后返回 `Promise`，用 `await`（Python 是 `.result()`）；③ 不传 config 的报错文本完全不同——TS 是 `Failed to put checkpoint. The passed RunnableConfig is missing a required "thread_id" field...`，不是 Python 的 `ValueError: Checkpointer requires...`。
> 💡 `interrupt()` 两侧都直接返回值（不抛异常），返回值形态也一致；TS 的 `__interrupt__` 数组元素是 `{ id, value }` 的普通对象（Python 是 `Interrupt` 命名元组）。

### 它的问题

1. **`clean` 没标 `@task`**——resume 时它会重跑。
2. **想改中间结果？**——没有具名字段。

> 🔑 **根因**：只加了"存档"的壳，没搞清楚**持久化的单位是什么**。

---

## 第 2 跳：撞上两个硬约束（问题被逼出来的下一步）

**坑一：没标 @task 的函数，resume 时必然重跑**

::: code-group

```python [Python]
from langgraph.types import Command

print("resume 前:", SIDE)
r2 = process.invoke(Command(resume="通过"), config=cfg)
print("resume ->", r2)
print(f"resume 后: {SIDE}")
```

```typescript [TypeScript]
import { Command } from "@langchain/langgraph";

console.log("resume 前:", JSON.stringify(SIDE));
const r2 = await process.invoke(new Command({ resume: "通过" }), cfg);
console.log("resume ->", JSON.stringify(r2));
console.log(`resume 后: ${JSON.stringify(SIDE)}`);
```

:::


实测输出：

```
resume 前: {'load': 1, 'clean': 1}
resume -> {'data': [1, 2, 3], 'approved': '通过'}
resume 后: {'load': 1, 'clean': 2}
```

TypeScript 侧：

```
resume 前: {"load":1,"clean":1}
resume -> {"data":[1,2,3],"approved":"通过"}
resume 后: {"load":1,"clean":2}
```

> ✅ **这一条两侧完全一致**——`load` 保持 1 次、`clean` 从 1 变 2。TS 的 `new Command({ resume: "通过" })` 与 Python 的 `Command(resume="通过")` 语义相同，只是要 `new`。

> ❌ **`clean` 从 1 次变成 2 次**——重跑了一遍。
> 🔑 **`load` 保持 1 次**（标了 `@task`，结果在存档点里），**`clean` 变成 2 次**（普通函数，没进存档点）。
> 💡 如果 `clean` 里有副作用（调外部接口、扣款、发消息），**副作用就重复发生了**。

**坑二：想改中间某一步的结果，做不到**

::: code-group

```python [Python]
st = process.get_state(cfg)
print("get_state ->", st.values)
print("历史条数:", len(list(process.get_state_history(cfg))))
```

```typescript [TypeScript]
const st = await process.getState(cfg);
console.log("getState ->", JSON.stringify(st.values));

// ⚠️ getStateHistory 返回异步迭代器，外层还要 await
const hist: any[] = [];
for await (const s of await process.getStateHistory(cfg)) hist.push(s);
console.log("历史条数:", hist.length);
console.log("next 形态:", JSON.stringify(hist.map((h) => h.next)));
```

:::


实测输出：

```
get_state -> {'data': [1, 2, 3], 'approved': '通过'}
历史条数: 2
```

TypeScript 侧：

```
getState -> {"data":[1,2,3],"approved":"通过"}
历史条数: 2
next 形态: [[],["process"]]
```

> ❌ **只有 2 条历史**：`()` 和 `('process',)`。
> 🔑 对照 Graph API——同样两步的流程有 **4 条**历史，而且能 `update_state({'某个字段': 新值})` 逐字段改。**Functional API 里 `previous` 是整体值，没有具名字段。**

> 💡 这两个坑的共性：**Functional API 的"状态"是粗粒度的**。它记得"上次交出来什么"（`previous`），但不记得"中间第几步算出了什么"。

---

## 第 3 跳：@task + previous 收口（综合）

![第 3 跳：@task + previous 收口](./assets/app-step2-functional-api.svg)

> 看图：所有有副作用的步骤都标 `@task`（绿色），`interrupt` 卡在中间（黄色），`previous` 承载跨轮状态（蓝色）。四块分别对应"全标 @task 的效果"、"改不了中间结果"、"选型判据"、"混用的坑"。

### 第一步：给所有有副作用的步骤标 @task

::: code-group

```python [Python]
SIDE2 = {"load": 0, "clean": 0, "write": 0}


@task
def load2(src: str) -> list:
    SIDE2["load"] += 1
    return [3, 1, 2]


@task
def clean2(data: list) -> list:
    SIDE2["clean"] += 1
    return sorted(data)


@task
def write2(data: list, ok) -> str:
    SIDE2["write"] += 1
    return f"写回 {len(data)} 条（审批={ok}）"


@entrypoint(checkpointer=InMemorySaver())
def process2(src: str) -> dict:
    data = load2(src).result()
    cleaned = clean2(data).result()
    ok = interrupt({"question": "确认", "data": cleaned})
    return {"result": write2(cleaned, ok).result()}


cfg2 = {"configurable": {"thread_id": "job-2"}}
r3 = process2.invoke("orders.csv", config=cfg2)
print("invoke ->", r3)
print(f"  计数: {SIDE2}")
r4 = process2.invoke(Command(resume="通过"), config=cfg2)
print("resume ->", r4)
print(f"  计数: {SIDE2}")
```

```typescript [TypeScript]
const SIDE2 = { load: 0, clean: 0, write: 0 };

const load2 = task("load2", async (src: string) => {
  SIDE2.load += 1;
  return [3, 1, 2];
});

const clean2 = task("clean2", async (data: number[]) => {
  SIDE2.clean += 1;
  return [...data].sort((a, b) => a - b);
});

const write2 = task("write2", async (data: number[], ok: unknown) => {
  SIDE2.write += 1;
  return `写回 ${data.length} 条（审批=${String(ok)}）`;
});

const process2 = entrypoint(
  { name: "process2", checkpointer: new MemorySaver() },
  async (src: string) => {
    const data = await load2(src);
    const cleaned = await clean2(data);
    const ok = interrupt({ question: "确认", data: cleaned });
    return { result: await write2(cleaned, ok) };
  }
);

const cfg2 = { configurable: { thread_id: "job-2" } };
const r3 = await process2.invoke("orders.csv", cfg2);
console.log("invoke ->", JSON.stringify(r3));
console.log(`  计数: ${JSON.stringify(SIDE2)}`);

const r4 = await process2.invoke(new Command({ resume: "通过" }), cfg2);
console.log("resume ->", JSON.stringify(r4));
console.log(`  计数: ${JSON.stringify(SIDE2)}`);
```

:::


实测输出：

```
invoke -> {'__interrupt__': [Interrupt(value={'question': '确认', 'data': [1, 2, 3]}, id='...')]}
  计数: {'load': 1, 'clean': 1, 'write': 0}
resume -> {'result': '写回 3 条（审批=通过）'}
  计数: {'load': 1, 'clean': 1, 'write': 1}
```

TypeScript 侧：

```
invoke -> {"__interrupt__":[{"id":"cb1f64ae...","value":{"question":"确认","data":[1,2,3]}}]}
  计数: {"load":1,"clean":1,"write":0}
resume -> {"result":"写回 3 条（审批=通过）"}
  计数: {"load":1,"clean":1,"write":1}
task 不是缓存：同 thread 再 invoke，load 计数 2 -> 3
```

> ✅ **`clean` 保持 1 次**——标了 `@task` 就不再重跑。三次 interrupt 的场景实测：3 个 task 只跑 3 次，不是 3×3。
> ⚠️ **但 `@task` 不是缓存**：同 thread 再 `invoke` 一次（不中断），实测执行次数照样 +1。它只在**从存档点恢复**时才体现价值。

### 第二步：previous 承载跨轮状态

::: code-group

```python [Python]
@entrypoint(checkpointer=InMemorySaver())
def pipeline(batch: list, previous=None) -> dict:
    done = (previous or {}).get("done", [])
    done = done + [len(batch)]
    return {"done": done, "total": sum(done)}


cfg3 = {"configurable": {"thread_id": "pipe"}}
print("第1批:", pipeline.invoke([1, 2], config=cfg3))
print("第2批:", pipeline.invoke([3, 4, 5], config=cfg3))
print("第3批:", pipeline.invoke([6], config=cfg3))
```

```typescript [TypeScript]
import { getPreviousState } from "@langchain/langgraph";

const pipeline = entrypoint(
  { name: "pipeline", checkpointer: new MemorySaver() },
  async (batch: number[]) => {
    // ⚠️ TS 回调只有 (input, config)，没有 previous 形参
    const prev = getPreviousState<{ done: number[] }>();
    const done = [...(prev?.done ?? []), batch.length];
    return { done, total: done.reduce((a, b) => a + b, 0) };
  }
);

const cfg3 = { configurable: { thread_id: "pipe" } };
console.log("第1批:", JSON.stringify(await pipeline.invoke([1, 2], cfg3)));
console.log("第2批:", JSON.stringify(await pipeline.invoke([3, 4, 5], cfg3)));
console.log("第3批:", JSON.stringify(await pipeline.invoke([6], cfg3)));
```

:::


实测输出：

```
第1批: {'done': [2], 'total': 2}
第2批: {'done': [2, 3], 'total': 5}
第3批: {'done': [2, 3, 1], 'total': 6}
```

TypeScript 侧（结果逐字一致）：

```
第1批: {"done":[2],"total":2}
第2批: {"done":[2,3],"total":5}
第3批: {"done":[2,3,1],"total":6}
```

> ✅ **`previous` 就是上一次的返回值**——天然累加，不用配 reducer。
> ⚠️ **但它是整体值**：你只能整体替换，不能说"把 total 改成 100"。

> ⚠️ **TS 没有 `previous` 形参**：`entrypoint` 回调只接受 `(input, config)`，第二个位置被 `config` 占了。要用 `getPreviousState<T>()` 从当前上下文里读——上例 `const prev = getPreviousState<{ done: number[] }>()`。首次调用它返回 `undefined`，所以要 `prev?.done ?? []`。

**对照 Graph API 的同样操作**：

::: code-group

```python [Python]
from langgraph.graph import END, START, StateGraph

b = StateGraph(dict)
b.add_node("add", lambda s: {"v": s.get("v", 0) + s.get("inc", 0)})
b.add_edge(START, "add")
b.add_edge("add", END)
g = b.compile(checkpointer=InMemorySaver())
cfgg = {"configurable": {"thread_id": "g"}}
print("Graph 第1次:", g.invoke({"v": 0, "inc": 10}, config=cfgg)["v"])
print("Graph 第2次:", g.invoke({"inc": 5}, config=cfgg)["v"])
```

```typescript [TypeScript]
import { StateGraph, Annotation, START, END } from "@langchain/langgraph";

const GState = Annotation.Root({
  v: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
  inc: Annotation<number>({ reducer: (_p, n) => n, default: () => 0 }),
});

const g = new StateGraph(GState)
  .addNode("add", (s: typeof GState.State) => ({ v: s.v + s.inc }))
  .addEdge(START, "add")
  .addEdge("add", END)
  .compile({ checkpointer: new MemorySaver() });

const cfgg = { configurable: { thread_id: "g" } };
console.log("Graph 第1次:", (await g.invoke({ v: 0, inc: 10 }, cfgg)).v);
// ⚠️ 只传增量：TS 会把存档点里的 v=10 带进来（Python 传 {} 时 v 缺省为 0，得到 5）
console.log("Graph 第2次:", (await g.invoke({ inc: 5 }, cfgg)).v);
// 显式把 v 归零，才是与 Python 对齐的「覆盖」语义
console.log("Graph 第2次（显式 v:0）:", (await g.invoke({ v: 0, inc: 5 }, cfgg)).v);
```

:::


实测输出：

```
Graph 第1次: 10
Graph 第2次: 5
```

TypeScript 侧这里有一处**结果不同**，值得单独记住：

```
Graph 第1次: 10
Graph 第2次（只传 inc）: 15   <- Python 是 5，TS 是 15
Graph 第2次（显式传 v:0）: 5
```

> 🔑 **同一件事两套写法结果不同**：Functional 的 `previous` 天然累加（2→5→6），Graph API 没配 reducer 就是**覆盖**（10→5）。
> 💡 想要 Graph 也累加，得给字段配 reducer（课 3 学过）——**这是"显式声明"与"隐式继承"的差别**。

> ⚠️ **注意 TS 那行 `15`**：Python 的 `invoke({"inc": 5})` 里 `v` 缺席、`s.get("v", 0)` 取到 0，所以是 5；TS 侧因为 `v` 声明了 `default: 0`，**未传的字段会沿用上一次的值**（上一轮 `v=10`；实测不挂 checkpointer 也是 15，属通道内的「上次值」机制），于是 `10 + 5 = 15`。想复现 Python 的"覆盖"效果，必须显式写 `{ v: 0, inc: 5 }`。这是 `Annotation` 的 `default` 与 Python `TypedDict` 缺省值之间的语义缝隙——**移植时要特别留意"没传字段"到底是 0 还是上一轮的值**。

### 第三步：混用——把旧图当函数调

::: code-group

```python [Python]
@task
def call_legacy_graph(x: int) -> int:
    return g.invoke({"v": x}, {"configurable": {"thread_id": f"legacy-{x}"}})["v"]


@entrypoint(checkpointer=InMemorySaver())
def mixed(x: int) -> dict:
    return {"out": call_legacy_graph(x).result()}


cfg4 = {"configurable": {"thread_id": "mix"}}
print("混用 ->", mixed.invoke(1, config=cfg4))
print("再来 ->", mixed.invoke(1, config=cfg4))
```

```typescript [TypeScript]
const callLegacyGraph = task("callLegacy", async (x: number) => {
  // ⚠️ 内层图的入参契约是它自己的 State schema，跟外层 Functional 的入参无关
  const r = await g.invoke({ v: x }, { configurable: { thread_id: `legacy-${x}` } });
  return r.v;
});

const mixed = entrypoint(
  { name: "mixed", checkpointer: new MemorySaver() },
  async (x: number) => ({ out: await callLegacyGraph(x) })
);

const cfg4 = { configurable: { thread_id: "mix" } };
console.log("混用 ->", JSON.stringify(await mixed.invoke(1, cfg4)));
console.log("再来 ->", JSON.stringify(await mixed.invoke(1, cfg4)));
```

:::


实测输出：

```
混用 -> {'out': 1}
再来 -> {'out': 1}
```

TypeScript 侧（一致）：

```
混用 -> {"out":1}
再来 -> {"out":1}
传全字段 -> {"out":11}
```

> ⚠️ **不是 12！** 内层图 `g` 的 `add` 节点是 `v = s.get("v",0) + s.get("inc",0)`，外层传进去的是 `{"v": x}`（没传 `inc`），所以就是 `1 + 0 = 1`。
>
> 🔑 **这个"意外"恰好演示了混用最容易踩的坑**：**内层图的入参契约是它自己的 State schema**，跟外层 Functional 的入参没关系。外层传 `x=1`，内层收到的是 `{"v": 1}`——**字段名对不上就静默取默认值**。
>
> 💡 而且两次调用结果一样，是因为内层图用了 `thread_id=f"legacy-{x}"`（同一个 x 同一个 thread），**第二次 invoke 时内层图的状态已经被前一次覆盖**——外层的 time-travel 完全管不到内层。

改法：显式传全内层图需要的字段，并让每次调用有独立 thread：

::: code-group

```python [Python]
@task
def call_legacy_graph(x: int) -> int:
    return g.invoke({"v": x, "inc": 10},
                    {"configurable": {"thread_id": f"legacy-{x}"}})["v"]
# -> {'out': 11}
```

```typescript [TypeScript]
const callLegacyFull = task("callLegacyFull", async (x: number) => {
  const r = await g.invoke(
    { v: x, inc: 10 },
    { configurable: { thread_id: `legacy-full-${x}` } }
  );
  return r.v;
});

const mixedFull = entrypoint(
  { name: "mixedFull", checkpointer: new MemorySaver() },
  async (x: number) => ({ out: await callLegacyFull(x) })
);

const c5 = { configurable: { thread_id: "mix2" } };
console.log("传全字段 ->", JSON.stringify(await mixedFull.invoke(1, c5)));   // -> {"out":11}
```

:::


> ✅ 实测 `11`。**但这仍不是"外层能管内层"**——只是把契约写全了。

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 得到的认识 |
|:--:|---------|-----------|
| 1 | `@entrypoint` + `@task` | 业务代码一行不动就有了存档点和暂停；但 `config` 必填 |
| 2 | resume 后数副作用 | **只有 `@task` 进存档点**，普通函数必重跑；没有具名字段 |
| 3 | 全标 `@task` + `previous` | `@task` 不是缓存；`previous` 天然累加但不能逐字段改；混用三个坑 |

**五条提醒**：

1. **只有 `@task` 进存档点**——普通函数在 resume 时必然重跑，副作用会重复。
2. **`@task` 不是缓存**——不中断时同 thread 再跑照样重算；真缓存要 `cache_policy` + `entrypoint(cache=...)`。
3. **挂了 checkpointer 必须传 `config`**——不传直接 `ValueError`。
4. **`previous` 是整体值**——历史只有 2 条（Graph 是 4 条），不能逐字段改。
5. **选型问一句**：中间过程要不要被单独看见和逐格改？要就 Graph，不要就 Functional。

🎯 **会用标志**：能给已有脚本加两个装饰器获得 checkpoint 与人在环中，能解释"为什么普通函数 resume 会重跑"，能说清 `previous` 与 Graph State 的差别并据此选型，能把已有的图包成 task 混用并知道三个坑。

### 🇹🇸 五条提醒在 TS 侧是否还成立

| # | Python 说法 | TS 侧实测 |
|:--:|------------|-----------|
| 1 | 只有 `@task` 进存档点，普通函数 resume 必然重跑 | ✅ 成立（`clean` 1→2，`load` 保持 1） |
| 2 | `@task` 不是缓存，同 thread 再跑照样重算 | ✅ 成立（`load` 计数 2→3） |
| 3 | 挂了 checkpointer 必须传 `config` | ✅ 成立，但**报错文本不同**（`Failed to put checkpoint... missing a required "thread_id"`） |
| 4 | `previous` 是整体值，历史只有 2 条 | ✅ 成立，但 **TS 没有 `previous` 形参**，要用 `getPreviousState<T>()` |
| 5 | 中间过程要不要被单独看见和逐格改 | ✅ 成立，判据两侧通用 |

### 🇹🇸 TS 写法对照表

| Python | TypeScript |
|--------|-----------|
| `@task` 装饰器 | `task("name", fn)`，名字必填，返回 `Promise` |
| `@entrypoint(checkpointer=...)` | `entrypoint({ name, checkpointer }, fn)`，选项在前 |
| `load(src).result()` | `await load(src)` |
| `f(x, previous=None)` | `async (x) => { getPreviousState<T>() }`（没有 previous 形参） |
| `process.invoke(..., config=cfg)` | `process.invoke(input, cfg)`（config 是第二位置参数） |
| `process.get_state(cfg)` | `await process.getState(cfg)` |
| `process.get_state_history(cfg)` | `for await (const s of await process.getStateHistory(cfg))` |
| `Command(resume="通过")` | `new Command({ resume: "通过" })` |
| `type(entrypoint(...)).__name__ == 'Pregel'` | `entrypoint(...).constructor.name === "Pregel"` |

## 回到开头的问题

同事问"要不要重写成 StateGraph？"

**看情况**——不是"哪个更好"，而是问：**中间过程要不要被单独看见和逐格改？**

- 如果这个流程将来要 **time-travel 改某一格**、要多个人照着拓扑接手、步骤会越来越复杂 → **用 Graph API**。
- 如果它就是个直脚本、改完就跑、团队更熟 Python → **Functional API 两个装饰器就够，别重写**。

两套 API **底层是同一个 Pregel 引擎**（实测 `type(entrypoint(...)).__name__ == 'Pregel'`），interrupt、回放、重试、流式全都对等——**所以这个选择不锁死，将来要换也有路**。
