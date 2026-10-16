# 应用实战 04：三份文档并行摘要后合并

> 对应：[课 4 Pregel 执行模型](../stages/2-执行模型与状态持久化/lessons/04-Pregel%20执行模型.md)
> 覆盖知识点：超级步执行模型 / Send 动态扇出 / Command 与状态更新、跳转
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）

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

```python
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

实测输出：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3
```

> ✅ 跑通了。但有两个问题：**份数写死在节点内部**（下次 5 份要改代码），而且**三份是串行做的**——慢。

---

## 第 2 跳：份数不定，用 Send 扇出（问题）

把"做几份"从节点里挪出来，交给 `Send` 在运行时决定。

```python
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

实测输出：

```
3 份 -> [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
5 份 -> [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策 / [doc4] 会员政策 / [doc5] 售后政策
```

> ✅ **份数从"写死"变成"运行时决定"**——换成 5 份，图一行没改。

> ⚠️ **这里有个必须注意的点**：`doc_name` / `doc_text` 是 `Send` **额外带进去的**，它们并不在 `State` 的声明里。实测能跑通，但依赖未声明字段属于隐式契约——**正式项目里建议把它们也写进 State**，否则课 5 加 checkpointer 后状态恢复容易踩坑。

---

## 第 3 跳：合并后总检，用 Command 一次干两件事（综合）

现在加一个总检：摘要份数不够就打回重做，够了就出报告。按课 3 的写法要拆成"总检节点 + 路由函数"两个；用 `Command` 一个就够。

```python
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

实测输出：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3
```

> ✅ `review` 一个节点**同时写了 `report` 又决定了去 `END`**——课 3 里那种"单独一个只看路的空节点"不需要了。

### 把 Command 的 goto 拼错试试（本课最该记住的坑）

把 `goto=END` 改成 `goto="ende"`，**并且去掉返回值上的 `Literal` 标注**：

```python
def review(state: State):            # 没有 -> Command[Literal[...]] 标注
    return Command(update={"report": "..."}, goto="ende")
```

实测：

```
报告： [doc1] 退款政策 / [doc2] 发票政策 / [doc3] 物流政策
摘要份数： 3        # 看起来"一切正常"
```

但 stderr 多了一行：

```
Task review with path ('__pregel_pull', 'review') wrote to unknown channel
branch:to:ende, ignoring it.
```

> ⚠️ **拼错的 goto 不会抛异常**，`invoke` 正常返回、结果看起来也对（因为 `update` 已经生效了）。**这类 bug 只在"目标节点本该跑却没跑"时才暴露**——排查时务必看 stderr。

**好消息**：把 `Literal` 标注加回去，写错的节点名会在**编译期**被抓住。实测：

```python
def review(state: State) -> Command[Literal["fan_out_again", "ende"]]:
    ...
```

```
ValueError: Found edge ending at unknown node `ende`
```

> ✅ 所以第 3 跳的那个 `-> Command[Literal["fan_out_again", END]]` **不是装饰，是护栏**。写 `Command` 时务必带上。

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
