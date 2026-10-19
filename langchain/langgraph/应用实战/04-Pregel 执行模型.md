# 应用实战 04：三份文档并行摘要后合并

> 对应：[课 4 Pregel 执行模型](../stages/2-执行模型与状态持久化/lessons/04-Pregel%20执行模型.md)
> 覆盖知识点：超级步执行模型 / Send 动态扇出 / Command 与状态更新、跳转
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）
> ✅ TypeScript 侧实测于 `playground-ts/`（`@langchain/langgraph` 1.5.1 / Node 20，`npm run a04`）

## 场景

客服助手要一次处理用户上传的**多份文档**，每份各出一段摘要，最后合并成一份报告。

三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 固定三份，串行摘要后合并 | 节点与边 / 累加 reducer |
| 问题 | 份数不定 + 想让质检一次干两件事 | Send 动态扇出 / Command |
| 综合 | 加上合并后的总检与回退上限 | Send + Command 配合 / 批数意识 |

---

## 第 1 跳：固定三份，串行处理（基础）

先跑通"每份摘要 → 合并"，不管份数。

::: code-group
```python [Python]
import operator
from typing import Annotated

from typing_extensions import TypedDict

from langgraph.graph import END, START, StateGraph

DOCS = {
    "doc1": "退款政策：签收后 7 天内可申请，商品需未使用。",
    "doc2": "发票政策：电子发票在订单完成后 24 小时内开出。",
    "doc3": "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
}


class State(TypedDict):
    docs: dict                                # 原始文档
    summaries: Annotated[list, operator.add]  # 累加：每份摘要都留下
    report: str


def summarize_all(state: State) -> dict:
    # 一次把三份都做完（串行）
    out = []
    for name, text in state["docs"].items():
        out.append(f"[{name}] {text.split('：')[0]}")
    return {"summaries": out}


def merge(state: State) -> dict:
    return {"report": " / ".join(state["summaries"])}


builder = StateGraph(State)
builder.add_node("summarize", summarize_all)
builder.add_node("merge", merge)
builder.add_edge(START, "summarize")
builder.add_edge("summarize", "merge")
builder.add_edge("merge", END)
app = builder.compile()

r = app.invoke({"docs": DOCS, "summaries": [], "report": ""})
print("报告：", r["report"])
print("摘要份数：", len(r["summaries"]))
```

```typescript [TypeScript]
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const DOCS: Record<string, string> = {
  doc1: "退款政策：签收后 7 天内可申请，商品需未使用。",
  doc2: "发票政策：电子发票在订单完成后 24 小时内开出。",
  doc3: "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
};

const State = Annotation.Root({
  docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
  // 累加：每份摘要都留下（等价于 Python 的 Annotated[list, operator.add]）
  summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

// 一次把三份都做完（串行）
const summarizeAll = (s: typeof State.State) => ({
  summaries: Object.entries(s.docs).map(([name, text]) => `[${name}] ${text.split("：")[0]}`),
});

const merge = (s: typeof State.State) => ({ report: s.summaries.join(" / ") });

const g = new StateGraph(State)
  .addNode("summarize", summarizeAll)
  .addNode("merge", merge)
  .addEdge(START, "summarize")
  .addEdge("summarize", "merge")
  .addEdge("merge", END)
  .compile();

const r = await g.invoke({ docs: DOCS, summaries: [], report: "" });
console.log("报告：", r.report);
console.log("摘要份数：", r.summaries.length);
```
:::

实测输出：

实测输出（Python）：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3
```

实测输出（TypeScript，`npm run a04`）：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3
```

> ✅ 跑通了。但有两个问题：**份数写死在节点内部**（下次 5 份要改代码），而且**三份是串行做的**——慢。

> 💡 逐字相同。TS 侧只有一处必改：`Annotation<Record<string, string>>` 与 `Annotation<string[]>` 都要显式给 `reducer` 和 `default`——TS 的 `Annotation` 没有 Python `Annotated[list, operator.add]` 那种"顺手挂 reducer"的写法，`concat` 就是 `operator.add` 的等价物。

---

## 第 2 跳：份数不定，用 Send 扇出（问题）

把"做几份"从节点里挪出来，交给 `Send` 在运行时决定。

::: code-group
```python [Python]
import operator
from typing import Annotated

from typing_extensions import TypedDict

from langgraph.graph import END, START, StateGraph
from langgraph.types import Send

DOCS = {
    "doc1": "退款政策：签收后 7 天内可申请，商品需未使用。",
    "doc2": "发票政策：电子发票在订单完成后 24 小时内开出。",
    "doc3": "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
}


class State(TypedDict):
    docs: dict
    summaries: Annotated[list, operator.add]
    report: str


def fan_out(state: State):
    # 运行时才决定开几份，每份只带自己那篇
    return [Send("summarize", {"doc_name": n, "doc_text": t})
            for n, t in state["docs"].items()]


def summarize(state: State) -> dict:
    name = state["doc_name"]
    text = state["doc_text"]
    return {"summaries": [f"[{name}] {text.split('：')[0]}"]}


def merge(state: State) -> dict:
    return {"report": " / ".join(sorted(state["summaries"]))}


builder = StateGraph(State)
builder.add_node("summarize", summarize)
builder.add_node("merge", merge)
builder.add_conditional_edges(START, fan_out)
builder.add_edge("summarize", merge)
builder.add_edge("merge", END)
app = builder.compile()

# 换成 5 份也不用改图
MORE_DOCS = dict(DOCS, doc4="会员政策：...", doc5="售后政策：...")
for docs in (DOCS, MORE_DOCS):
    r = app.invoke({"docs": docs, "summaries": [], "report": ""})
    print(f"{len(docs)} 份 ->", r["report"])
```

```typescript [TypeScript]
import { Annotation, END, START, Send, StateGraph } from "@langchain/langgraph";

const DOCS: Record<string, string> = {
  doc1: "退款政策：签收后 7 天内可申请，商品需未使用。",
  doc2: "发票政策：电子发票在订单完成后 24 小时内开出。",
  doc3: "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
};

const State = Annotation.Root({
  docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
  // ⚠️ 这里把 doc_name / doc_text 显式声明了（比 Python 示例多做一步，见下方提醒）
  doc_name: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  doc_text: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

// 运行时才决定开几份，每份只带自己那篇（TS 侧用 new Send(...) 构造）
const fanOut = (s: typeof State.State) =>
  Object.entries(s.docs).map(([n, t]) => new Send("summarize", { doc_name: n, doc_text: t }));

const summarize = (s: typeof State.State) => ({
  summaries: [`[${s.doc_name}] ${s.doc_text.split("：")[0]}`],
});

const merge = (s: typeof State.State) => ({ report: [...s.summaries].sort().join(" / ") });

const g = new StateGraph(State)
  .addNode("summarize", summarize)
  .addNode("merge", merge)
  // ⚠️ TS 侧第三个参数必须把可能的去向列全
  .addConditionalEdges(START, fanOut, ["summarize"])
  .addEdge("summarize", "merge")
  .addEdge("merge", END)
  .compile();

// 换成 5 份也不用改图
const MORE_DOCS = { ...DOCS, doc4: "会员政策：...", doc5: "售后政策：..." };
for (const docs of [DOCS, MORE_DOCS]) {
  const r = await g.invoke({ docs, summaries: [], report: "" });
  console.log(`${Object.keys(docs).length} 份 ->`, r.report);
}
```
:::

实测输出：

实测输出（Python）：

```
3 份 -> [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
5 份 -> [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策 / [doc4] 会员政策 / [doc5] 售后政策
```

实测输出（TypeScript）：

```
3 份 -> [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
5 份 -> [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策 / [doc4] 会员政策 / [doc5] 售后政策
```

> ✅ **份数从"写死"变成"运行时决定"**——换成 5 份，图一行没改。

> 💡 TS 侧三处写法差异：①`Send` 要用 `new Send("summarize", {...})` 构造，不是直接调函数；②`addConditionalEdges(START, fanOut, ["summarize"])` 必须补第三个参数列出去向；③`{ ...DOCS, doc4: "..." }` 用展开运算符，对应 Python 的 `dict(DOCS, doc4=...)`。

> ⚠️ **这里有个必须注意的点**：`doc_name` / `doc_text` 是 `Send` **额外带进去的**，它们并不在 `State` 的声明里。实测能跑通，但依赖未声明字段属于隐式契约——**正式项目里建议把它们也写进 State**，否则课 5 加 checkpointer 后状态恢复容易踩坑。

> 💡 **TS 侧没有这个"可省"的余地**：上面 TS 代码里 `doc_name` / `doc_text` 是**显式声明**进 `State` 的。TS 的 `Annotation.Root` 同时充当类型定义，`Send` 里传的键必须先在 `Annotation` 里存在，否则 `tsc --noEmit` 直接报类型错——**Python 的隐式契约在 TS 侧变成了编译期硬约束**，反而更安全。

---

## 第 3 跳：合并后总检，用 Command 一次干两件事（综合）

现在加一个总检：摘要份数不够就打回重做，够了就出报告。按课 3 的写法要拆成"总检节点 + 路由函数"两个；用 `Command` 一个就够。

::: code-group
```python [Python]
import operator
from typing import Annotated, Literal

from typing_extensions import TypedDict

from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, Send

DOCS = {
    "doc1": "退款政策：签收后 7 天内可申请，商品需未使用。",
    "doc2": "发票政策：电子发票在订单完成后 24 小时内开出。",
    "doc3": "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
}
MIN_SUMMARIES = 3
MAX_ROUNDS = 2


class State(TypedDict):
    docs: dict
    doc_name: str
    doc_text: str
    summaries: Annotated[list, operator.add]
    rounds: Annotated[list, operator.add]
    report: str


def fan_out(state: State):
    n = len(state["rounds"])
    if n >= MAX_ROUNDS:
        return "review"          # 次数用尽，直接去总检
    return [Send("summarize", {"doc_name": k, "doc_text": v})
            for k, v in state["docs"].items()]


def summarize(state: State) -> dict:
    if "doc_name" not in state:
        return {}
    return {"summaries": [f"[{state['doc_name']}] {state['doc_text'].split('：')[0]}"]}


def review(state: State) -> Command[Literal["fan_out_again", END]]:
    """一次干两件事：记下这一轮 + 决定下一步去哪。"""
    ok = len(state["summaries"]) >= MIN_SUMMARIES
    if ok or len(state["rounds"]) >= MAX_ROUNDS:
        return Command(update={"report": " / ".join(sorted(state["summaries"]))},
                       goto=END)
    return Command(update={"rounds": ["重做一轮"]}, goto="fan_out_again")


def fan_out_again(state: State):
    return [Send("summarize", {"doc_name": k, "doc_text": v})
            for k, v in state["docs"].items()]


builder = StateGraph(State)
builder.add_node("fan_out_again", fan_out_again)
builder.add_node("summarize", summarize)
builder.add_node("review", review)
builder.add_conditional_edges(START, fan_out)
builder.add_edge("summarize", "review")
builder.add_edge("fan_out_again", "summarize")
app = builder.compile()

r = app.invoke({"docs": DOCS, "doc_name": "", "doc_text": "",
                "summaries": [], "rounds": [], "report": ""},
               {"recursion_limit": 50})
print("报告：", r["report"])
print("摘要份数：", len(r["summaries"]))
```

```typescript [TypeScript]
import { Annotation, Command, END, START, Send, StateGraph } from "@langchain/langgraph";

const DOCS: Record<string, string> = {
  doc1: "退款政策：签收后 7 天内可申请，商品需未使用。",
  doc2: "发票政策：电子发票在订单完成后 24 小时内开出。",
  doc3: "物流政策：默认快递 48 小时内发货，偏远地区顺延。",
};
const MIN_SUMMARIES = 3;
const MAX_ROUNDS = 2;

const State = Annotation.Root({
  docs: Annotation<Record<string, string>>({ reducer: (_p, n) => n, default: () => ({}) }),
  doc_name: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  doc_text: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  summaries: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  rounds: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  report: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const fanOut = (s: typeof State.State) => {
  if (s.rounds.length >= MAX_ROUNDS) return "review"; // 次数用尽，直接去总检
  return Object.entries(s.docs).map(
    ([k, v]) => new Send("summarize", { doc_name: k, doc_text: v })
  );
};

const summarize = (s: typeof State.State) => ({
  // Python 版判的是 "doc_name" in state；TS 侧字段有 default，只能判值
  summaries: s.doc_name ? [`[${s.doc_name}] ${s.doc_text.split("：")[0]}`] : [],
});

// 一次干两件事：记下这一轮 + 决定下一步去哪
const review = (s: typeof State.State) => {
  const ok = s.summaries.length >= MIN_SUMMARIES;
  if (ok || s.rounds.length >= MAX_ROUNDS) {
    return new Command({
      update: { report: [...s.summaries].sort().join(" / ") },
      goto: END,
    });
  }
  return new Command({ update: { rounds: ["重做一轮"] }, goto: "fan_out_again" });
};

const fanOutAgain = (s: typeof State.State) =>
  Object.entries(s.docs).map(([k, v]) => new Send("summarize", { doc_name: k, doc_text: v }));

const g = new StateGraph(State)
  // ⚠️ TS 侧节点返回 Command 时，要用 ends 声明所有可能目标（替代 Python 的 Literal 标注）
  .addNode("fan_out_again", fanOutAgain)
  .addNode("summarize", summarize)
  .addNode("review", review, { ends: ["fan_out_again", END] })
  .addConditionalEdges(START, fanOut, ["summarize", "review"])
  .addEdge("summarize", "review")
  .addEdge("fan_out_again", "summarize")
  .compile();

const r = await g.invoke(
  { docs: DOCS, doc_name: "", doc_text: "", summaries: [], rounds: [], report: "" },
  { recursionLimit: 50 } // 驼峰，不是 recursion_limit
);
console.log("报告：", r.report);
console.log("摘要份数：", r.summaries.length);
```
:::

实测输出：

实测输出（Python）：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3
```

实测输出（TypeScript）：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3
```

> ✅ `review` 一个节点**同时写了 `report` 又决定了去 `END`**——课 3 里那种"单独一个只看路的空节点"不需要了。

> 💡 TS 侧这一跳有两个必须改的地方：①`review` 返回 `Command` 跳转时，`addNode` 必须带 `{ ends: ["fan_out_again", END] }`——**它就是 Python `-> Command[Literal[...]]` 标注的等价物**；②`summarize` 不能写 `if "doc_name" not in state`（TS 的字段有 `default`，永远存在），只能判值 `s.doc_name ? [...] : []`。另外 `recursion_limit` 在 TS 侧是驼峰的 `recursionLimit`。

### 把 Command 的 goto 拼错试试（本课最该记住的坑）

把 `goto=END` 改成 `goto="ende"`，**并且去掉返回值上的 `Literal` 标注**：

::: code-group
```python [Python]
def review(state: State):            # 没有 -> Command[Literal[...]] 标注
    return Command(update={"report": "..."}, goto="ende")
```

```typescript [TypeScript]
// 没有 ends 声明
const review = (_s: typeof State.State) =>
  new Command({ update: { report: "..." }, goto: "ende" });
```
:::

实测（Python）：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3        # 看起来"一切正常"
```

但 stderr 多了一行：

```
Task review with path ('__pregel_pull', 'review') wrote to unknown channel
branch:to:ende, ignoring it.
```

实测（TypeScript）：

```
编译通过（TS 侧不用 ends 也能过）
invoke 返回： {"report":"...","rounds":[]}
```

TS 侧**连 stderr 都没有**——stdout / stderr 分别重定向后确认，两边都是干净的。

> ⚠️ **拼错的 goto 不会抛异常**，`invoke` 正常返回、结果看起来也对（因为 `update` 已经生效了）。**这类 bug 只在"目标节点本该跑却没跑"时才暴露**——排查时务必看 stderr。

> ⚠️ **TS 侧比 Python 更危险一层**：Python 至少会在 stderr 留一条 `wrote to unknown channel ... ignoring it` 的痕迹，TS 侧**完全静默**——没有异常、没有警告、返回值也带着 `report`。也就是说，同样一个拼写错误，Python 还能靠 stderr 捞回来，TS 只能靠测试或日志。

**好消息**：把 `Literal` 标注加回去，写错的节点名会在**编译期**被抓住。实测：

::: code-group
```python [Python]
def review(state: State) -> Command[Literal["fan_out_again", "ende"]]:
    ...
```

```typescript [TypeScript]
const review = (_s: typeof State.State) =>
  new Command({ update: { report: "..." }, goto: "ende" });

new StateGraph(State)
  // ends 里写错的名字会在编译期被抓住
  .addNode("review", review, { ends: ["fan_out_again", "ende"] })
  .addEdge(START, "review")
  .addEdge("summarize", "review")
  .addEdge("fan_out_again", "summarize")
  .compile();
```
:::

实测（Python）：

```
ValueError: Found edge ending at unknown node `ende`
```

实测（TypeScript）：

```
编译期报错: Error: Found edge ending at unknown node `ende`
```

> ✅ 所以第 3 跳的那个 `-> Command[Literal["fan_out_again", END]]` **不是装饰，是护栏**。写 `Command` 时务必带上。

> 💡 报错文案两侧**逐字相同**（`Found edge ending at unknown node \`ende\``），差别只在异常类：Python 抛 `ValueError`，TS 抛 `Error`。TS 侧对应的护栏写法是 `addNode(name, fn, { ends: [...] })`，`ends` 里的每个名字同样会在**编译期**被校验。

> 💡 一个实测踩到的坑：`ends` 写错时如果图里还缺边，先报的可能是 `UnreachableNodeError: Node \`summarize\` is not reachable.` 而不是 `unknown node`——因为可达性检查排在名字校验之前。把边补全后才会看到那条和 Python 对齐的 `unknown node` 报错。

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 得到的认识 |
|:--:|---------|-----------|
| 1 | 串行循环 + `Annotated[list, add]` | 份数写死在节点里，改需求要改代码 |
| 2 | `add_conditional_edges(START, fan_out)` + `list[Send]` | 份数运行时决定；**接收字段必须有 reducer** |
| 3 | `Command(update=..., goto=...)` | 干活 + 指路合一；**goto 拼错静默失败** |

**两个提醒**：

1. `Send` 分支的返回值都写回同一个共享状态字段，所以那个字段**必须有 reducer**（本课用的 `operator.add`）。
2. 本课第 2 跳用到的 `doc_name` / `doc_text` 没有写进 State 声明也能跑，但这是隐式契约——**正式项目请显式声明**，否则课 5 加了 checkpointer 之后状态恢复会出问题。

### TS 侧写法对照

| 跳 | Python | TypeScript |
|:--:|--------|-----------|
| 1 | `Annotated[list, operator.add]` | `Annotation<string[]>({ reducer: (a, b) => a.concat(b) })` |
| 2 | `Send("summarize", {...})` | `new Send("summarize", {...})`（必须 `new`） |
| 2 | `add_conditional_edges(START, fan_out)` | `addConditionalEdges(START, fanOut, ["summarize"])`（**必须列全去向**） |
| 2 | `dict(DOCS, doc4="...")` | `{ ...DOCS, doc4: "..." }` |
| 3 | `if "doc_name" not in state` | `s.doc_name ? ... : ...`（字段有 `default`，永远存在） |
| 3 | `-> Command[Literal["fan_out_again", END]]` | `addNode("review", review, { ends: ["fan_out_again", END] })` |
| 3 | `{"recursion_limit": 50}` | `{ recursionLimit: 50 }`（驼峰） |
