# 应用实战 03：把"一次通过"的客服流程改成带质检回退的循环

> 对应：[课 3 Graph API 第一个图](../stages/1-从create_agent到StateGraph/lessons/03-Graph%20API%20第一个图.md)
> 覆盖知识点：State 的定义与 reducer / 节点与边 / 条件边与循环
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）
> ✅ TypeScript 侧实测于 `playground-ts/`（`@langchain/langgraph` 1.5.1 / Node 20，`npm run a03`）

## 场景

客服助手第一版是"一次通过"：用户提问 → 生成回复 → 发出去。质检同事反馈**明显不合格的回答也被直接发出去了**。

本实战做三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 跑通"一次通过"的直线图 | State / 节点 / 边 / START 与 END |
| 问题 | 发现劣质回答被发出去，加质检与回退 | 条件边 / 循环 / reducer 累加历史 |
| 综合 | 加上"改不好就放弃"的上限与兜底回复 | 终止条件 / recursion_limit 保险丝 |

---

## 第 1 跳：一次通过（基础）

先跑通最简单的直线：提问 → 生成 → 结束。

::: code-group
```python [Python]
from typing_extensions import TypedDict

from langgraph.graph import END, START, StateGraph

KNOWLEDGE = {
    "退款": "退款需在签收后 7 天内申请，且商品未使用。",
}


class State(TypedDict):
    question: str
    answer: str


def answer_node(state: State) -> dict:
    q = state["question"]
    # 简化：命中知识库就照抄，否则给一个空泛回复
    return {"answer": KNOWLEDGE.get(q.strip(), "您好，已收到您的反馈。")}


builder = StateGraph(State)
builder.add_node("answer", answer_node)
builder.add_edge(START, "answer")
builder.add_edge("answer", END)
app = builder.compile()

print(app.invoke({"question": "退款", "answer": ""}))
print(app.invoke({"question": "怎么申请发票", "answer": ""}))
```

```typescript [TypeScript]
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const KNOWLEDGE: Record<string, string> = {
  退款: "退款需在签收后 7 天内申请，且商品未使用。",
};

const State = Annotation.Root({
  question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const g = new StateGraph(State)
  // ⚠️ 节点名不能与状态字段同名（课 3 已记录），所以叫 generate 而不是 answer
  .addNode("generate", (s) => ({
    answer: KNOWLEDGE[s.question.trim()] ?? "您好，已收到您的反馈。",
  }))
  .addEdge(START, "generate")
  .addEdge("generate", END)
  .compile();

console.log(await g.invoke({ question: "退款", answer: "" }));
console.log(await g.invoke({ question: "怎么申请发票", answer: "" }));
```
:::


实测输出（Python）：

```
{'question': '退款', 'answer': '退款需在签收后 7 天内申请，且商品未使用。'}
{'question': '怎么申请发票', 'answer': '您好，已收到您的反馈。'}
```

实测输出（TypeScript，`npm run a03`）：

```
{ question: '退款', answer: '退款需在签收后 7 天内申请，且商品未使用。' }
{ question: '怎么申请发票', answer: '您好，已收到您的反馈。' }
```

> ✅ 跑通了。但第二个问题已经是**劣质回答**——它什么都没解决，却被原样发出去。
> 💡 只是一处表象差异：Python 打印 dict 带引号，TS 打印对象的键不带引号，**内容逐字相同**。另外 TS 侧节点名从 `answer` 改成了 `generate`——**节点名不能与状态字段同名**（课 3 已记录），否则 `addNode` 当场抛 `answer is already being used as a state attribute`。

---

## 第 2 跳：加质检与回退（问题）

现在加一个质检节点：不合格就打回重写。这里有两个新东西：

- `history` 字段要用 `Annotated[list[str], add]` **累加**（否则只留最后一版，课 3 坑 1）
- 用 `add_conditional_edges` 挂路由函数决定"放行还是回退"

::: code-group
```python [Python]
from operator import add
from typing import Annotated

from typing_extensions import TypedDict

from langgraph.graph import END, START, StateGraph

KNOWLEDGE = {"退款": "退款需在签收后 7 天内申请，且商品未使用。"}


class State(TypedDict):
    question: str
    answer: str
    history: Annotated[list[str], add]   # 累加：每版都留着
    verdict: str


def draft_node(state: State) -> dict:
    n = len(state["history"])
    if n == 0:
        ans = KNOWLEDGE.get(state["question"].strip(), "您好，已收到您的反馈。")
    else:
        # 第二版起：改用"查知识库 + 承认不确定"的写法
        ans = KNOWLEDGE.get(state["question"].strip(),
                            f"关于「{state['question']}」，我目前没有可靠信息，已为您转人工。")
    return {"answer": ans, "history": [f"第{n + 1}版：{ans}"]}


def check_node(state: State) -> dict:
    # 判定规则：空泛回复 = 不合格（真实场景这里调模型）
    bad = state["answer"] == "您好，已收到您的反馈。"
    return {"verdict": "打回" if bad else "通过"}


def route(state: State) -> str:
    return END if state["verdict"] == "通过" else "draft"


builder = StateGraph(State)
builder.add_node("draft", draft_node)
builder.add_node("check", check_node)
builder.add_edge(START, "draft")
builder.add_edge("draft", "check")
builder.add_conditional_edges("check", route)
app = builder.compile()

r = app.invoke({"question": "怎么申请发票", "answer": "", "history": [], "verdict": ""})
print("最终回复：", r["answer"])
print("改写历史：")
for h in r["history"]:
    print("  -", h)
```

```typescript [TypeScript]
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const KNOWLEDGE: Record<string, string> = {
  退款: "退款需在签收后 7 天内申请，且商品未使用。",
};

const State = Annotation.Root({
  question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  // 累加：每版都留着（等价于 Python 的 Annotated[list[str], add]）
  history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  verdict: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const draft = (s: typeof State.State) => {
  const n = s.history.length;
  const ans =
    n === 0
      ? (KNOWLEDGE[s.question.trim()] ?? "您好，已收到您的反馈。")
      : (KNOWLEDGE[s.question.trim()] ??
        `关于「${s.question}」，我目前没有可靠信息，已为您转人工。`);
  return { answer: ans, history: [`第${n + 1}版：${ans}`] };
};

const check = (s: typeof State.State) => ({
  verdict: s.answer === "您好，已收到您的反馈。" ? "打回" : "通过",
});

const route = (s: typeof State.State) => (s.verdict === "通过" ? END : "draft");

const g = new StateGraph(State)
  .addNode("draft", draft)
  .addNode("check", check)
  .addEdge(START, "draft")
  .addEdge("draft", "check")
  // ⚠️ TS 侧要把所有可能的去向写进第三个参数，否则运行期抛 UnreachableNodeError
  .addConditionalEdges("check", route, ["draft", END])
  .compile();

const r = await g.invoke({
  question: "怎么申请发票",
  answer: "",
  history: [],
  verdict: "",
});
console.log("最终回复：", r.answer);
console.log("改写历史：");
for (const h of r.history) console.log("  -", h);
```
:::


实测输出（Python）：

```
最终回复： 关于「怎么申请发票」，我目前没有可靠信息，已为您转人工。
改写历史：
  - 第1版：您好，已收到您的反馈。
  - 第2版：关于「怎么申请发票」，我目前没有可靠信息，已为您转人工。
```

实测输出（TypeScript）：

```
最终回复： 关于「怎么申请发票」，我目前没有可靠信息，已为您转人工。
改写历史：
  - 第1版：您好，已收到您的反馈。
  - 第2版：关于「怎么申请发票」，我目前没有可靠信息，已为您转人工。
```

> ✅ **两侧逐字相同**。唯一要改的写法是条件边的第三个参数：Python 的 `add_conditional_edges("check", route)` 两参数即可，TS 必须写成 `addConditionalEdges("check", route, ["draft", END])`，把所有可能去向列全，否则运行期抛 `UnreachableNodeError`。

> ✅ 劣质回答被拦下来了，而且**两版都留着**——这正是 `Annotated[list[str], add]` 的功劳。如果这里用了普通 `list`，`history` 只会剩最后一版（课 3 验证一实测）。

> ⚠️ **但这一跳有个隐患**：如果"第二版"也永远不合格（比如判定规则写错了），这个循环会**一直转下去**。

---

## 第 3 跳：加上限与兜底（综合）

真实的循环需要两道保险：**显式的放弃条件**（改 N 次还不行就转人工）+ `recursion_limit`（万一你漏写了放弃条件）。

::: code-group
```python [Python]
from operator import add
from typing import Annotated

from typing_extensions import TypedDict

from langgraph.graph import END, START, StateGraph

MAX_ROUNDS = 3
KNOWLEDGE = {"退款": "退款需在签收后 7 天内申请，且商品未使用。"}


class State(TypedDict):
    question: str
    answer: str
    history: Annotated[list[str], add]
    verdict: str


def draft_node(state: State) -> dict:
    n = len(state["history"])
    if n == 0:
        ans = KNOWLEDGE.get(state["question"].strip(), "您好，已收到您的反馈。")
    elif n < MAX_ROUNDS - 1:
        # 中间版：换个写法再试
        ans = KNOWLEDGE.get(state["question"].strip(),
                            f"关于「{state['question']}」，我目前没有可靠信息，已为您转人工。")
    else:
        # 最后一版：不再硬编，直接给兜底回复
        ans = "抱歉，这个问题我反复确认后仍无法给出可靠答复，已转人工客服，请稍候。"
    return {"answer": ans, "history": [f"第{n + 1}版：{ans}"]}


def check_node(state: State) -> dict:
    # 故意写死"前 MAX_ROUNDS 版都不合格"，用来验证放弃条件是否生效
    bad = len(state["history"]) < MAX_ROUNDS
    return {"verdict": "打回" if bad else "通过"}


def route(state: State) -> str:
    if state["verdict"] == "通过":
        return END
    if len(state["history"]) >= MAX_ROUNDS:
        return END
    return "draft"


builder = StateGraph(State)
builder.add_node("draft", draft_node)
builder.add_node("check", check_node)
builder.add_edge(START, "draft")
builder.add_edge("draft", "check")
builder.add_conditional_edges("check", route)
app = builder.compile()

# 第二道保险：recursion_limit 当保险丝
r = app.invoke({"question": "怎么申请发票", "answer": "", "history": [], "verdict": ""},
               {"recursion_limit": 25})
print("最终回复：", r["answer"])
print("共改写：", len(r["history"]), "版")
```

```typescript [TypeScript]
import { Annotation, END, START, StateGraph } from "@langchain/langgraph";

const MAX_ROUNDS = 3;
const KNOWLEDGE: Record<string, string> = {
  退款: "退款需在签收后 7 天内申请，且商品未使用。",
};

const State = Annotation.Root({
  question: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  answer: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
  history: Annotation<string[]>({ reducer: (a, b) => a.concat(b), default: () => [] }),
  verdict: Annotation<string>({ reducer: (_p, n) => n, default: () => "" }),
});

const draft = (s: typeof State.State) => {
  const n = s.history.length;
  let ans: string;
  if (n === 0) {
    ans = KNOWLEDGE[s.question.trim()] ?? "您好，已收到您的反馈。";
  } else if (n < MAX_ROUNDS - 1) {
    ans =
      KNOWLEDGE[s.question.trim()] ??
      `关于「${s.question}」，我目前没有可靠信息，已为您转人工。`;
  } else {
    ans = "抱歉，这个问题我反复确认后仍无法给出可靠答复，已转人工客服，请稍候。";
  }
  return { answer: ans, history: [`第${n + 1}版：${ans}`] };
};

const check = (s: typeof State.State) => ({
  verdict: s.history.length < MAX_ROUNDS ? "打回" : "通过",
});

const route = (s: typeof State.State) => {
  if (s.verdict === "通过") return END;
  if (s.history.length >= MAX_ROUNDS) return END;
  return "draft";
};

const g = new StateGraph(State)
  .addNode("draft", draft)
  .addNode("check", check)
  .addEdge(START, "draft")
  .addEdge("draft", "check")
  .addConditionalEdges("check", route, ["draft", END])
  .compile();

// 第二道保险：recursionLimit 当保险丝（TS 侧是驼峰，不是 recursion_limit）
const r = await g.invoke(
  { question: "怎么申请发票", answer: "", history: [], verdict: "" },
  { recursionLimit: 25 }
);
console.log("最终回复：", r.answer);
console.log("共改写：", r.history.length, "版");
```
:::


实测输出（Python）：

```
最终回复： 抱歉，这个问题我反复确认后仍无法给出可靠答复，已转人工客服，请稍候。
共改写： 3 版
```

实测输出（TypeScript）：

```
最终回复： 抱歉，这个问题我反复确认后仍无法给出可靠答复，已转人工客服，请稍候。
共改写： 3 版
```

三版历史（实测）：

```
  - 第1版：您好，已收到您的反馈。
  - 第2版：关于「怎么申请发票」，我目前没有可靠信息，已为您转人工。
  - 第3版：抱歉，这个问题我反复确认后仍无法给出可靠答复，已转人工客服，请稍候。
```

> ✅ 三跳走完，流程从"劣质回答直接发出"变成了"最多改 3 版 + 兜底转人工"。
>
> 💡 注意 `draft_node` 里的边界是 `n < MAX_ROUNDS - 1` 而不是 `n < MAX_ROUNDS`——因为 `n` 是**已写完的版数**，要留出最后一版专门给兜底回复。差一位就会变成"第 3 版还是硬编的回复，兜底永远不出现"（我实测撞过一次）。

### 把保险丝拆掉会发生什么

把 `route` 里的放弃条件删掉，只留 `return "draft"`，再看 `recursion_limit` 的作用：

::: code-group
```python [Python]
def route_no_stop(state: State) -> str:
    return "draft"      # 永远回退
```

```typescript [TypeScript]
const routeNoStop = (_s: typeof State.State) => "draft" as const;   // 永远回退
```
:::


实测（Python）：

```
GraphRecursionError: Recursion limit of 25 reached without hitting a stop condition.
You can increase the limit by setting the `recursion_limit` config key.
```

实测（TypeScript）：

```
GraphRecursionError: Recursion limit of 25 reached without hitting a stop condition.
You can increase the limit by setting the "recursionLimit" config key.
```

> 💡 异常类名与前半句**逐字相同**，只有配置键名一个蛇形一个驼峰（`recursion_limit` ↔ `recursionLimit`）。

> ⚠️ **注意**：超限是**抛异常**，用户拿到的是一次失败请求，不是那个兜底回复。所以 `recursion_limit` **只能当保险丝，不能当终止条件**——这一条是课 3 的核心结论。

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 踩到的坑 |
|:--:|---------|---------|
| 1 | `add_edge(START/END)`、节点返回部分更新 | 节点不返回 = 状态不变 |
| 2 | `add_conditional_edges` + 路由函数 | 历史字段忘加 `add` → 只留最后一版 |
| 3 | 路由里写放弃条件 + `recursion_limit` 兜底 | 只有上限没有终止条件 → 抛异常 |

**一个提醒**：本课所有 reducer 用的都是 `operator.add`，它对 list 是**拼接**。如果你想让 `history` 去重、或给消息做"同 id 覆盖"语义，需要自定义 reducer——那是课 6《Store 长期记忆》附近会遇到的 `add_messages` 话题。
