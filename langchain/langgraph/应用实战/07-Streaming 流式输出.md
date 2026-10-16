# 应用实战 07：把黑盒客服改成边跑边说

> 对应：[课 7 Streaming 流式输出](../stages/2-执行模型与状态持久化/lessons/07-Streaming%20流式输出.md)
> 覆盖知识点：流模式 / 事件流与子图事件
> ✅ 全部代码实测于 langgraph 1.2.11 / Python 3.12（在 `../langchain/playground` 以 `uv run` 隔离执行）

## 场景

客服助手跑一次要十几秒：检索 → 生成 → 校对。用户点下去屏幕全白，以为它死了。

三跳演进：

| 跳 | 目标 | 新增的知识点 |
|:--:|------|-------------|
| 基础 | 让它每做完一步说一声 | values / updates 选型 |
| 问题 | 让它说"查到第几条 / 还差多少" | custom + get_stream_writer |
| 综合 | 子图里的进度也要看得见 | 事件流 / subgraphs=True |

> 完整方案还需要：SSE / WebSocket 推送、断线重连、背压与节流、鉴权、消息序号与幂等——**这些都不是本课内容**（课 13 部署时展开）。

---

## 第 1 跳：让它每做完一步说一声（基础）

图一行不改，把 `invoke` 换成 `stream`。

![第 1 跳：让它每做完一步就说一声](./assets/app-step1-streaming.svg)

> 看图：左右是同一张图，区别只在"要的方式"。`invoke` 三步全黑、最后才给一条答案；`stream(updates)` 每步吐一个 `{节点名: 改动}`。

```python
from langgraph.graph import END, START, StateGraph
from typing_extensions import TypedDict


class State(TypedDict):
    question: str
    docs: list
    draft: str
    final: str


def retrieve(state: State) -> dict:
    return {"docs": ["文档A", "文档B"]}


def generate(state: State) -> dict:
    return {"draft": f"基于{len(state['docs'])}篇的草稿"}


def proofread(state: State) -> dict:
    return {"final": state["draft"] + "（已校对）"}


builder = StateGraph(State)
for name, fn in [("检索", retrieve), ("生成", generate), ("校对", proofread)]:
    builder.add_node(name, fn)
builder.add_edge(START, "检索")
builder.add_edge("检索", "生成")
builder.add_edge("生成", "校对")
builder.add_edge("校对", END)
graph = builder.compile()

inp = {"question": "怎么退款", "docs": [], "draft": "", "final": ""}

print("--- invoke（只有终态）---")
print(graph.invoke(inp)["final"])

print("--- stream(updates)（逐节点）---")
for chunk in graph.stream(inp, stream_mode="updates"):
    node = list(chunk.keys())[0]
    print(f"  完成：{node}")
```

实测输出：

```
--- invoke（只有终态）---
基于2篇的草稿（已校对）
--- stream(updates)（逐节点）---
  完成：检索
  完成：生成
  完成：校对
```

### 为什么选 `updates` 不选 `values`

```
values（全量重发，3 节点 → 4 个 chunk，含初始状态）：
  {'question':'怎么退款','docs':[],'draft':'','final':''}
  {'question':'怎么退款','docs':['文档A','文档B'],'draft':'','final':''}
  {'question':'怎么退款','docs':['文档A','文档B'],'draft':'基于2篇的草稿','final':''}
  {'question':'怎么退款','docs':['文档A','文档B'],'draft':'基于2篇的草稿','final':'基于2篇的草稿（已校对）'}

updates（只给改动，3 个）：
  {'检索': {'docs': ['文档A','文档B']}}
  {'生成': {'draft': '基于2篇的草稿'}}
  {'校对': {'final': '基于2篇的草稿（已校对）'}}
```

> ✅ 只想看"做到第几步"，`updates` 就够了——`values` 每次把整个状态重发一遍，状态越大越浪费。

### 它的问题

1. **节点内部还是黑盒**——"检索"这一步花 5 秒，中间查到第几条你不知道。
2. **没有自定义进度**——想显示"还差一半"做不到。

> 🔑 **根因**：`updates` 的粒度是"一个节点结束"，不是"节点内部进行到哪"。

---

## 第 2 跳：让它说"还差多少"（问题被逼出来的下一步）

在节点里用 `get_stream_writer()` 主动喊话。

```python
from langgraph.config import get_stream_writer


def retrieve_v2(state: State) -> dict:
    w = get_stream_writer()
    found = []
    for i, name in enumerate(["文档A", "文档B", "文档C"], 1):
        found.append(name)
        w({"step": "检索", "current": i, "total": 3, "msg": f"查到 {name}"})   # ← 喊一嗓子
    return {"docs": found}


def generate_v2(state: State) -> dict:
    w = get_stream_writer()
    w({"step": "生成", "progress": 0.5, "msg": "写了一半"})
    w({"step": "生成", "progress": 1.0, "msg": "写完了"})
    return {"draft": f"基于{len(state['docs'])}篇的草稿"}


builder2 = StateGraph(State)
builder2.add_node("检索", retrieve_v2)
builder2.add_node("生成", generate_v2)
builder2.add_node("校对", proofread)
builder2.add_edge(START, "检索")
builder2.add_edge("检索", "生成")
builder2.add_edge("生成", "校对")
builder2.add_edge("校对", END)
graph2 = builder2.compile()

print("--- stream(custom)：节点里喊的话 ---")
for data in graph2.stream(inp, stream_mode="custom"):
    print(f"  {data}")
```

实测输出：

```
--- stream(custom)：节点里喊的话 ---
  {'step': '检索', 'current': 1, 'total': 3, 'msg': '查到 文档A'}
  {'step': '检索', 'current': 2, 'total': 3, 'msg': '查到 文档B'}
  {'step': '检索', 'current': 3, 'total': 3, 'msg': '查到 文档C'}
  {'step': '生成', 'progress': 0.5, 'msg': '写了一半'}
  {'step': '生成', 'progress': 1.0, 'msg': '写完了'}
```

> ✅ 前端拿到就能渲染进度条了。

### ⚠️ 这一步的坑：不声明 `custom` 就白喊

```python
# 你以为写了就能收到：
list(graph2.stream(inp, stream_mode="values"))
# -> 只有状态，custom 数据一个都没有，且不报错
```

实测：

```
stream_mode='values' -> [{'docs':[],...}, {'docs':[...],...}, ...]   # 自定义数据没了
stream_mode='custom' -> [{'step':'检索',...}, ...]                    # 要这样才收得到
```

> 🔑 **写 `get_stream_writer()` 不等于有人听**——必须显式声明 `stream_mode="custom"`，否则**静默丢弃**。

### 两个模式一起要

```python
for mode, chunk in graph2.stream(inp, stream_mode=["updates", "custom"]):
    if mode == "custom":
        print(f"  进度 {chunk}")
    else:
        print(f"  完成 {list(chunk.keys())[0]}")
```

> ✅ 输出是 `(模式, 数据)` 元组且**交错**——不是先吐完一种再吐另一种。

---

## 第 3 跳：子图里的进度也要看得见（综合）

真实的生成步骤往往是个子图。这时候进度会"消失"。

![第 3 跳：多模式分工 + 前端消费](./assets/app-step2-streaming.svg)

> 看图：高亮部分是本跳新增——子图要可见、`custom` 要声明、前端按 `type` 分流。**三条铁律都在红框里**（全是实测撞出来的静默失败）。

```python
# 子图：内部也会喊话
class SubState(TypedDict):
    docs: list
    draft: str


def sub_search(state: SubState) -> dict:
    w = get_stream_writer()
    w({"from": "子图-查资料", "progress": 0.5})
    return {"docs": state.get("docs", []) + ["补充文档"]}


def sub_write(state: SubState) -> dict:
    w = get_stream_writer()
    w({"from": "子图-写草稿", "progress": 1.0})
    return {"draft": f"基于{len(state['docs'])}篇的草稿"}


sb = StateGraph(SubState)
sb.add_node("查资料", sub_search)
sb.add_node("写草稿", sub_write)
sb.add_edge(START, "查资料")
sb.add_edge("查资料", "写草稿")
sb.add_edge("写草稿", END)
sub = sb.compile()          # ← 编译成子图


# 父图：把编译好的子图直接当节点
def generate_v3(state: State) -> dict:
    r = sub.invoke({"docs": state["docs"], "draft": ""})
    return {"draft": r["draft"]}


builder3 = StateGraph(State)
builder3.add_node("检索", retrieve_v2)
builder3.add_node("生成", generate_v3)      # ← 子图在这里
builder3.add_node("校对", proofread)
builder3.add_edge(START, "检索")
builder3.add_edge("检索", "生成")
builder3.add_edge("生成", "校对")
builder3.add_edge("校对", END)
graph3 = builder3.compile()
```

**先撞一次坑**——子图里的进度去哪了：

```python
print("--- 不开 subgraphs：子图的 custom 收不到 ---")
print(list(graph3.stream(inp, stream_mode="custom")))
```

```
--- 不开 subgraphs：子图的 custom 收不到 ---
[]
```

> ❌ **空的**。父图节点自己喊的话能收到，子图里的**一个都收不到**。

**加上 `subgraphs=True`**：

```python
print("--- 开 subgraphs=True ---")
for ns, data in graph3.stream(inp, stream_mode="custom", subgraphs=True):
    where = "/".join(n.split(":")[0] for n in ns) or "主图"
    print(f"  [{where}] {data}")
```

实测输出：

```
--- 开 subgraphs=True ---
  [主图] {'step': '检索', 'current': 1, 'total': 3, 'msg': '查到 文档A'}
  [主图] {'step': '检索', 'current': 2, 'total': 3, 'msg': '查到 文档B'}
  [主图] {'step': '检索', 'current': 3, 'total': 3, 'msg': '查到 文档C'}
  [生成] {'from': '子图-查资料', 'progress': 0.5}
  [生成] {'from': '子图-写草稿', 'progress': 1.0}
```

> ✅ 开了之后，`ns` 里带上了子图路径（`生成:uuid`），**主图和子图的进度都能区分来源了**。

### 前端怎么消费

一次 stream 同时喂饱两种 UI：

```python
for ns, mode, payload in graph3.stream(inp, stream_mode=["updates", "custom"], subgraphs=True):
    where = "/".join(n.split(":")[0] for n in ns) or "主图"
    if mode == "custom":
        print(f"  进度条 [{where}] {payload}")
    else:
        print(f"  步骤条 [{where}] 完成 {list(payload.keys())[0]}")
```

实测输出：

```
  进度条 [主图] {'step': '检索', 'current': 1, 'total': 3, 'msg': '查到 文档A'}
  步骤条 [主图] 完成 检索
  进度条 [生成] {'from': '子图-查资料', 'progress': 0.5}
  步骤条 [生成] 完成 查资料
  进度条 [生成] {'from': '子图-写草稿', 'progress': 1.0}
  步骤条 [生成] 完成 写草稿
  步骤条 [主图] 完成 生成
  步骤条 [主图] 完成 校对
```

> ⚠️ **这里有个坑**：多模式 + `subgraphs=True` 时，吐出来的是 **`(ns, mode, data)` 三元组**，不是二元组。实测：
>
> ```
> ((),                    'custom',  {'p': 1})
> (('n2:daea5cca-...',),  'custom',  {'from': 'sub'})
> (('n2:daea5cca-...',),  'updates', {'sn': {'out': 'A+'}})
> ```
>
> 用 `for mode, payload in ...` 解包会直接 **`ValueError: too many values to unpack (expected 2)`**。
> ✅ **组合规则**：单独开 `subgraphs` → `(ns, data)`；多模式 → `(mode, data)`；**两个都开 → `(ns, mode, data)`**。

### 三条铁律（全是实测撞出来的静默失败）

| # | 铁律 | 撞出来的现象 |
|:-:|---|---|
| 1 | **不声明 `custom` = 丢弃** | 节点里 writer 写了，前端一个字都收不到，**且不报错** |
| 2 | **子图动静要 `subgraphs=True`** | 默认子图全程隐身，`custom` 数据也靠它才冒泡 |
| 3 | **`v2` 结构要取 `data`** | 默认吐 `{'type','ns','data','interrupts'}`，别当裸字典用 |

> ⚠️ 第 3 条实测对照：
>
> ```
> version='v2'（默认）: [{'type':'values','ns':(),'data':{...},'interrupts':()}, ...]
> version='v1'        : [{...}, {...}]          ← 老教程的裸字典写法
> ```

---

## 收尾：三跳带走了什么

| 跳 | 关键代码 | 得到的认识 |
|:--:|---------|-----------|
| 1 | `stream(mode="updates")` | 图不用改；看进度用 `updates` 而非 `values` |
| 2 | `get_stream_writer()` + `mode="custom"` | 自定义进度；**不声明就静默丢弃** |
| 3 | `subgraphs=True` | 子图事件与 `custom` 都要它才冒泡 |

**四个提醒**：

1. **看全貌用 `values`、看进度用 `updates`**——选错直接影响带宽与前端渲染。
2. **`custom` 必须声明**，否则静默丢弃且不报错。
3. **子图的一切动静要 `subgraphs=True`**，包括 `custom` 数据。
4. **`v2` 的输出是包装字典**——老教程 `for state in stream(...)` 当字典用是 `v1` 写法。

🎯 **会用标志**：能独立把一张黑盒图改成"步骤条 + 进度条"双路输出，说清为什么 `custom` 要显式声明、为什么子图要 `subgraphs=True`，并能解释 `v1` / `v2` 输出结构的差别。
