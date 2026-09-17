# 第 6 课：Streaming 流式输出（让循环的过程实时可见）

> 所属阶段：阶段 2《Agent 核心》｜ 水平：进阶（有扎实 Python 与后端工程基础，LangChain 从零）｜ 本课知识点：流式的价值与机制、流模式全解、实战流式模式
> 故事情节：引擎转起来了——但用户盯着空屏等结果，中间发生了什么一概不知。本课把"转的过程"变成实时可见的流：逐字输出、工具进度、思考过程，全部摊开
> 📖 结论已按官方文档核对（核对于 2026-09 ｜ 来源：docs.langchain.com 的 streaming / event-streaming 页；三种流模式、v2/v3 协议、custom 信号、reasoning tokens 等结论为本机实测）

## 🎯 本课目标

- 说清流式为什么重要、底层怎么传输（「流式的价值与机制」）
- 掌握三种流模式（updates / messages / custom）的用途与区别（「流模式全解」）
- 能做出打字机效果、工具进度条，并了解 v3 事件流新写法（「实战流式模式」）

---

## 第一幕：起源与场景引入

> 🏛️ **起源**：流式输出（streaming）在 LLM 领域并非 LangChain 首创——OpenAI 在 2023 年 3 月的 Chat Completion API 中首次支持 `stream=True`，让 token 逐个返回而非等全文生成完毕。LangChain 在此基础上做了两件事：① 把流式从"模型层"提升到"agent 层"——不只是模型 token 能流，agent 的每一步（工具调用、状态更新、自定义信号）都能流；② 提供统一的 v2/v3 流协议，让前端、中间件、调试工具都能用同一套事件格式消费（核对于 2026-09）。

客服助手第五次进化。上一课你给它装好了引擎——`create_agent` 一行组装，循环自己转，结果也能结构化输出。跑起来之后，你发现一个新问题。

**用户盯着空屏等**。问一句"帮我查下北京天气"，屏幕上一片空白——2.8 秒后突然蹦出一整段答案。这 2.8 秒里发生了什么？模型在想什么？工具调了没？用户不知道，你也不知道（除非翻日志）。

更糟的是，如果任务复杂——查订单、算账、设提醒——用户可能等 5 秒、8 秒甚至更久。空屏等待是体验杀手。

> 🎬 **场景**：把 `invoke`（一次性返回）换成 `stream`（逐步输出）——模型每想出一个 token 就递给你，工具每执行一步就通知你。用户看到的是"打字机效果"而非"空屏等待"，你看到的是"每步进度"而非"黑盒结果"。

> 📌 **一句话本质**：stream 不是"另一种调用"——是**同一次调用，边跑边报**。invoke 把中间过程藏起来、只给你最终结果；stream 把中间过程拆成一个个 chunk，实时递给你（核对于 2026-09）。
>
> ⚖️ **处境对照**：不这么写——invoke 返回前用户盯空屏（本课实测：2.8 秒无任何反馈），调试靠事后翻 `messages` 列表。这么写——stream 首 chunk 在 1.4 秒即到达（实测），用户看到"正在查天气…"→"北京：晴天 22°C"→逐字输出终答；调试时每一步的节点名、消息类型、tool_calls 状态全部实时可见。

---

## 第二幕：认知冲突

第一次听到"流式输出"，很容易把它理解成"另一种 API 调用方式"——就像 `invoke` 和 `stream` 是两个不同的函数，走不同的路径。

这个理解是错的。

**`invoke` 和 `stream` 走的是同一条路**——同一个 agent、同一个引擎、同一段循环。区别只在于"结果怎么给你"：invoke 把中间过程攒在内部，最后一次性打包返回；stream 每完成一步就立刻递一个 chunk 出来。

> ❓ **问题**：stream 到底能"流"出什么？三种模式分别解决什么问题——如果我只想要打字机效果，该用哪个？

三个追问把这件事拆开：

- 追问一：**"流"的到底是什么？**——不是"整个答案"，而是**引擎每一步的产物**：模型调用完成 → 一个 chunk（含 tool_calls 状态）；工具执行完成 → 一个 chunk（含 ToolMessage）；模型逐 token 生成 → 每个 token 一个 chunk。**三种粒度对应三种需求**：看进度用 updates、做打字机用 messages、发自定义信号用 custom。
- 追问二：**三种模式能混用吗？**——能。`stream_mode=["updates", "custom"]` 会同时输出两种 chunk，每个 chunk 带 `type` 字段区分来源。v2 协议统一了格式：每个 chunk 都是 `{"type": "updates|messages|custom", "ns": [...], "data": ...}`。
- 追问三：**v3 事件流又是什么？和 v2 什么关系？**——v2 是 LangGraph 底层的流协议（`stream()` 方法），v3 是 LangChain v1.3 引入的**上层封装**（`stream_events()` 方法）。v3 把 v2 的"按 mode 分 chunk"升级为"按投影（projection）分迭代器"——`stream.messages` 拿模型输出、`stream.tool_calls` 拿工具执行、`stream.values` 拿状态快照，各自独立迭代，不用再 `if chunk["type"] == "messages"` 分支判断。官方推荐新项目用 v3。

由此得到本课的第一个关键认知：**流式不是"另一种调用"，是"同一次调用的不同交付方式"**。invoke 是"全部做完再给你"，stream 是"做一步给一步"——引擎没变、循环没变、工具没变，变的是**你什么时候拿到信息**。

---

## 第三幕：层层揭示

### 一眼全局图（进入细节前先看一眼）

![从「等它转完」到「看它转」](../assets/lesson-06-overview.svg)

> 看图：左边是上一课的状态——invoke 一次性返回，用户盯空屏；右边是本课——stream 逐步输出，每步可见；底部是三站卡片（为什么需要流式 → 三种模式怎么用 → 实战怎么接）。

### 本课地图（分几步走）

| 步 | 这一步要解决什么（人话） | 对应知识点 |
|:--:|------------------------|-----------|
| 1 | 流式到底解决了什么问题、底层怎么传输 | 知识点 1：流式的价值与机制 |
| 2 | updates / messages / custom 三种模式各流什么、怎么选 | 知识点 2：流模式全解 |
| 3 | 打字机效果、工具进度条、v3 事件流新写法 | 知识点 3：实战流式模式 |

### 知识点 1：流式的价值与机制

> 🧭 第 1/3 步｜承接：第二幕的追问「流式到底流什么、和 invoke 什么关系」 → 本步：invoke vs stream 对照实测，说清底层机制

#### 一句话定义

流式输出（streaming）让 agent 的每一步执行结果**实时递送**给调用方，而不是等全部完成后一次性返回。LangChain 提供三种流粒度（进度 / token / 自定义信号）和两套协议（v2 统一格式 / v3 事件流投影）。

#### 直觉建立（类比）

外卖 App 的订单追踪：invoke 是你下单后 App 只显示"已送达"——中间骑手取餐、在路上、还有 500 米，你全看不见。stream 是 App 实时显示"商家已接单 → 骑手已取餐 → 骑手距你 1.2km → 骑手距你 500m → 已送达"——同样的配送过程，但你每一步都知道进度。

> 💡 **类比的边界**：外卖追踪是 GPS 信号（独立于配送的数据源）；agent 的 stream 是**同一次调用的产物**——不是额外开了个"监控通道"，而是把原本攒在内部的结果**拆开递出来**。所以 stream 不会让 agent 跑得更快或更慢，只改变**你什么时候看到什么**。

#### 核心原理

**① invoke vs stream：同一条路，不同交付方式**——实测对照（脚本 1 段）：

```text
[非流式 invoke] 开始计时…
  耗时 2.8s
  终答: 北京现在是晴天，气温22°C，湿度45%。…

[流式 stream(updates)] 开始计时…
  [1.4s] 收到 chunk: updates
    节点 model: （空内容——模型只申请了工具，还没说话）
  [1.4s] 收到 chunk: updates
    节点 tools: 北京：晴天，22°C，湿度 45%
  [2.8s] 收到 chunk: updates
    节点 model: 北京今天是晴天，气温22°C，湿度45%。
  总耗时 2.8s
```

同一个 agent、同一个问题——总耗时完全一样（2.8 秒）。区别在于：invoke 让你干等 2.8 秒才看到结果；stream 在 1.4 秒时就告诉你"模型已经决定调工具了"、紧接着告诉你"工具返回了天气数据"、最后逐字输出终答。**用户 1.4 秒就看到反馈，而不是 2.8 秒**。

**② 三种粒度，一张表说清**（官方 streaming 页定义，本课实测验证）：

| 模式 | 流什么 | 一个 chunk 长什么样 | 典型用途 |
|------|--------|-------------------|----------|
| `updates` | 每个节点执行完后的状态更新 | `{"type":"updates", "data":{"model":{"messages":[...]}}}` | 进度条、步骤指示器 |
| `messages` | LLM 每次生成的 token chunk | `{"type":"messages", "data":(AIMessageChunk, metadata)}` | 打字机效果（逐字输出） |
| `custom` | 工具/节点内手动发送的信号 | `{"type":"custom", "data":"正在搜索…"}` | 工具进度、自定义事件 |

**③ v2 统一格式**——从 LangGraph 1.1 起，`stream(version="v2")` 让所有 chunk 共享同一结构：

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "..."}]},
    stream_mode=["updates", "custom"],
    version="v2",
):
    print(chunk["type"])   # "updates" 或 "custom"
    print(chunk["data"])   # 对应的负载
```

不再需要 `for mode, chunk in agent.stream(...)` 这种元组解包——`chunk["type"]` 统一分拣。v2 是当前默认推荐（v1 为向后兼容保留）。

**④ v3 事件流：从"按 mode 分 chunk"到"按投影分迭代器"**——LangChain v1.3 引入 `stream_events(version="v3")`，官方推荐新项目使用：

```python
stream = agent.stream_events(
    {"messages": [{"role": "user", "content": "..."}]},
    version="v3",
)

for message in stream.messages:      # 模型输出投影
    for delta in message.text:       # 逐块迭代（文本投影）
        print(delta, end="", flush=True)

final_state = stream.output          # 最终状态
```

v3 的核心变化：**不再需要 `if chunk["type"] == "messages"` 分支判断**——`stream.messages`、`stream.tool_calls`、`stream.values` 各自是独立的迭代器，类型安全、IDE 友好。本机实测验证了基本用法：`message.text` 是可迭代的文本投影（实测类型 `SyncTextProjection`，本次迭代 6 个文本块）——与官方文档示例写法一致；需注意当前版本（langgraph 1.2.11）v3 协议标记为 `LangChainBetaWarning`（experimental）。

#### 示例演示

见上文实测：invoke vs stream 对照（①）、三种模式定义（②）、v2 格式（③）、v3 事件流（④），来源脚本 `playground/lesson-06-streaming-lab.py`。

#### 常见误区

1. **以为 stream 是"另一种调用"**：同一个 agent、同一条路——invoke 攒着给，stream 拆开给（实测总耗时完全一样）。
2. **以为 stream 会让 agent 跑得更快**：它只改变"你什么时候看到"，不改变"引擎跑多久"——总耗时不变（实测 2.8s）。
3. **以为 v3 已经完全稳定**：当前版本标记为 `LangChainBetaWarning`（experimental），生产环境建议 v2 为主、v3 为辅。

#### 一句话记住

> invoke 是"做完再给"，stream 是"做一步给一步"——引擎没变，交付方式变了。

#### 🗣️ 行话对照

- **streaming / 流式输出**：逐块递送而非一次性返回——在哪遇到：`agent.stream()`、`stream_mode` 参数
- **chunk**：流式输出中的一块数据——在哪遇到：`for chunk in agent.stream(...)`
- **stream_mode**：流的粒度（updates / messages / custom）——在哪遇到：`stream()` 的 `stream_mode` 参数
- **v2 / v3 protocol**：流事件格式版本——在哪遇到：`version="v2"` / `version="v3"`
- **stream_events**：v3 事件流 API——在哪遇到：`agent.stream_events()`
- **projection**：v3 中的类型化数据视图（messages / tool_calls / values）——在哪遇到：`stream.messages`、`stream.tool_calls`

#### 官方文档

- [Streaming（三种模式、v2 格式、常见模式）](https://docs.langchain.com/oss/python/langchain/streaming)
- [Event streaming（v3 协议、typed projections）](https://docs.langchain.com/oss/python/langchain/event-streaming)

---

### 知识点 2：流模式全解

> 🧭 第 2/3 步｜承接：知道了流式"是什么"，现在搞清楚三种模式各流什么、怎么选 → 本步：updates / messages / custom 逐一实测，多模式混用

#### 一句话定义

LangChain 提供三种流模式：`updates`（每节点执行完后的状态更新）、`messages`（LLM 每个 token chunk）、`custom`（工具/节点内手动发送的自定义信号）。三种模式可单独使用也可组合（`stream_mode=["updates", "custom"]`）。

#### 直觉建立（类比）

看一场球赛的三种直播方式：**updates** = 每节结束后的比分播报（只看结果）；**messages** = 逐帧画面（每个动作都看到）；**custom** = 解说员插播的场外消息（"球员 A 正在热身"）。你可以只看比分、只看画面、只听解说——也可以同时开着三种。

> 💡 **类比的边界**：球赛的三种信号来自不同的摄像机；agent 的三种模式来自**同一次调用的不同切面**——updates 是"状态快照"、messages 是"生成过程"、custom 是"你主动塞进去的信号"。

#### 核心原理

**① updates：每步结束报进度**——实测（脚本 2 段）：

```text
共收到 3 个 chunk
  chunk 1: 节点 ['model']
    model → AIMessage (tool_calls=True)
  chunk 2: 节点 ['tools']
    tools → ToolMessage (tool_calls=False)
  chunk 3: 节点 ['model']
    model → AIMessage (tool_calls=False)
```

三个 chunk 对应课 5 的 agent loop 三步：模型申请工具 → 工具执行 → 模型终答。每个 chunk 告诉你**哪个节点刚刚完成、产出了什么类型的消息、有没有 tool_calls**。这就是"agent 进度条"的数据源——前端收到 chunk 1 显示"思考中…"，收到 chunk 2 显示"查询天气中…"，收到 chunk 3 显示最终答案。

**② messages：每个 token chunk 都给你**——实测（脚本 3 段）：

```text
逐块输出（内容块一行，截断显示）:
  [model] '北京是中国'
  [model] '的首都，也是一'
  [model] '座融合了悠久历史'
  [model] '与现代'
  [model] '活力的国际化大都市。'
  （共 39 个 chunk：内容块 5 个（即上方 5 行）+ 空增量 34 个，空增量已跳过）
```

每个 chunk 是一个 `(AIMessageChunk, metadata)` 元组。`AIMessageChunk` 是 `AIMessage` 的流式版本——它的 `content_blocks` 属性包含本次增量（可能是一个词、一个标点、或一个 tool_call_chunk）。`metadata` 里有关键字段 `langgraph_node`（告诉你这个 token 来自哪个节点）。

注意两个实测现象：① **文本块粒度取决于模型**——本机 qwen3.8-flash 一次回答是"几个字一块"（实测 5 个文本块 / 37 字），不是逐字，不同模型的分块策略不同，不要把"逐 token"理解成"逐汉字"；② **流中混有大量空增量 chunk**——本机实测一次调用 39 个 chunk 中 34 个为空（`content` 为空、无内容块），做打字机效果必须判空后再输出（见知识点 3）。

**③ custom：工具里随时发信号**——实测（脚本 4 段）：

```text
自定义进度信号:
  📡 🔍 正在搜索：LangChain streaming latest documentation
  📡 📊 已检索 3 条数据库记录
  📡 ✅ 搜索完成
  📡 🔍 正在搜索：LangChain astream stream mode values updates messages documentation
  📡 🔍 正在搜索：LangChain docs streaming tokens Runnable.stream callback handler
  📡 📊 已检索 3 条数据库记录
  📡 📊 已检索 3 条数据库记录
  📡 ✅ 搜索完成
  📡 ✅ 搜索完成
```

实现方式——在工具函数内调用 `get_stream_writer()`：

```python
from langgraph.config import get_stream_writer

@tool
def slow_search(query: str) -> str:
    writer = get_stream_writer()
    writer(f"🔍 正在搜索：{query}")
    # …执行搜索…
    writer(f"✅ 搜索完成")
    return f"关于「{query}」找到 3 条结果：……"
```

然后 `stream_mode="custom"` 就能收到这些信号。注意实测中的一个现象：**当模型并行调用多个工具时，custom 信号会交错**（上例中 3 次搜索的进度信号混在一起）。这是正常的——custom 信号按实际执行顺序到达，不保证按工具调用顺序排列。

**④ 多模式混用**——`stream_mode=["updates", "custom"]` 同时输出两种 chunk，用 `chunk["type"]` 区分：

```python
for chunk in agent.stream(
    {"messages": [...]},
    stream_mode=["updates", "custom"],
    version="v2",
):
    if chunk["type"] == "updates":
        # 处理状态更新
    elif chunk["type"] == "custom":
        # 处理自定义信号
```

三种模式可以任意组合——`["updates", "messages", "custom"]` 全开也行，但注意 messages 模式 chunk 量很大（每个 token 一个），混用时做好过滤。

#### 示例演示

见上文实测：updates 三节点进度（①）、messages 逐 token（②）、custom 工具信号（③）、多模式混用（④），来源脚本 `playground/lesson-06-streaming-lab.py`。

#### 常见误区

1. **以为"逐 token"就是"逐汉字"**：粒度由模型决定——本机 qwen3.8-flash 是"几个字一块"（实测 5 个文本块覆盖整句，其间另有数十个空增量 chunk）。
2. **以为 custom 信号会按工具调用顺序排列**：并行调用时信号交错（实测 3 次搜索的进度混在一起）——如需严格顺序，在工具内自行排队。
3. **以为 messages 模式只流文本**：它也会流 tool_call_chunk（工具调用的参数增量）——做"工具调用进度条"时注意过滤。

#### 一句话记住

> updates 看进度、messages 看字、custom 看信号——三种模式同一来源，按需组合。

#### 🗣️ 行话对照

- **updates mode**：状态更新流——在哪遇到：`stream_mode="updates"`
- **messages mode**：LLM token 流——在哪遇到：`stream_mode="messages"`
- **custom mode**：自定义信号流——在哪遇到：`stream_mode="custom"`、`get_stream_writer()`
- **AIMessageChunk**：AIMessage 的流式片段——在哪遇到：messages 模式的 chunk data
- **get_stream_writer**：获取流写入器——在哪遇到：`langgraph.config`

#### 官方文档

- [Streaming · Supported stream modes](https://docs.langchain.com/oss/python/langchain/streaming#supported-stream-modes)
- [Streaming · Custom updates](https://docs.langchain.com/oss/python/langchain/streaming#custom-updates)

---

### 知识点 3：实战流式模式

> 🧭 第 3/3 步｜承接：三种模式会用了——现在把它们接成真实场景：打字机效果、工具进度条、v3 新写法、多 agent 标注 → 本步：四个实战模式 + v3 事件流深入

#### 一句话定义

实战流式 = 把三种流模式接成用户可感知的体验：打字机效果（messages 模式逐 token 打印）、工具进度条（custom 模式发进度信号）、思考过程可见（reasoning tokens）、多 agent 来源标注（sub-agents 的 name 参数）。v3 事件流（`stream_events`）是官方推荐的新写法，用 typed projections 替代分支判断。

#### 直觉建立（类比）

三种"直播"接成一台完整的节目：**打字机效果** = 字幕逐字出现（messages）；**工具进度条** = 画面角落的"正在连线前方记者…"（custom）；**思考过程** = 解说员的分析旁白（reasoning）；**多 agent 标注** = 画面上方显示当前信号源（"北京演播室" / "前方记者"）。

> 💡 **类比的边界**：真实直播的"字幕""旁白""信号源标注"是后期合成的；agent 的流式是**实时原生**的——每个信号都是引擎执行过程中真实产生的，不需要事后拼接。

#### 核心原理

**① 打字机效果**——最简单的实战：`stream_mode="messages"` + 逐 token 打印：

```python
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "用一句话介绍北京。"}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        token, _ = chunk["data"]
        if token.content:                        # 关键：判空，跳过空增量
            print(token.content, end="", flush=True)
```

两个关键点：① `end=""` 不换行 + `flush=True` 强制刷新——否则终端会等缓冲区满了才显示，打字机效果出不来；② **判空**——实测流中大多数 chunk 是空增量（一次调用 39 个中 34 个为空），不判空会让输出空转、逻辑难排查。

**② 工具进度条**——`stream_mode="custom"` + `get_stream_writer()`（知识点 2 已演示）。进阶用法：结合 `stream_mode=["updates", "custom"]`，用 updates 跟踪当前步骤、用 custom 显示工具内部进度。

**③ 思考过程可见（reasoning tokens）**——部分模型（如 Claude、支持 reasoning 的 OpenAI 模型）在生成最终答案前会先输出"思考"内容。官方给出两条接收路径：`stream_mode="messages"` 下过滤 `type="reasoning"` 的内容块，或 v3 事件流的 `message.reasoning` 投影。本机实测（qwen3.8-flash + 百炼端点，简单问题）：未产生独立 reasoning 流——v3 的 `message.reasoning` 投影存在但迭代 0 项（是否输出思考内容与模型及端点通道有关）。要用好这一能力，先按官方 streaming 页确认你的模型/端点会发出 reasoning 块，再上 UI。

**④ 多 agent 来源标注**——当 agent A 调用 agent B（通过工具）时，`stream_mode="messages"` + `subgraphs=True` 可以在 metadata 中拿到 `lc_agent_name`，区分当前 token 来自哪个 agent。给每个 `create_agent` 传 `name="weather_agent"` 等参数即可启用。

**⑤ v3 事件流深入**——本机实测（脚本 5 段 + 评审核查补充）：

```text
v3 事件流（messages 投影）:
  [model] 广州当前天气：晴天，气温 22°C，湿度 45%。天气不错，适合外出～

投影形态实测（评审核查脚本）:
  message.text       类型 SyncTextProjection —— 迭代出 6 个文本块（拼接为上方回答）
  message.reasoning  类型 SyncTextProjection —— 迭代出 0 项（本轮无思考内容）

最终状态 keys: ['messages']
```

v3 基本用法验证通过：`stream.messages` 逐块拿模型输出（`for delta in message.text` 写法成立）、`stream.output` 拿最终状态。两个实测要点：

- **`message.text` 是可迭代文本投影**（实测类型 `SyncTextProjection`）——迭代产出文本块，与官方文档示例一致；`message.reasoning` 同为投影（本轮 0 项，见 ③）。
- **v3 协议当前标记为 `LangChainBetaWarning`（experimental）**——终端输出中明确提示。生产环境建议 v2 为主、v3 为辅，等协议稳定后再全面迁移。

#### 示例演示

见上文实测：打字机效果（①，判空版示例经补测验证）、工具进度条（②）、v3 事件流（⑤），来源脚本 `playground/lesson-06-streaming-lab.py`；reasoning tokens（③）本机实测未产生独立输出、多 agent 标注（④）为官方文档归纳（均如实标注）。

#### 常见误区

1. **以为 v3 已经可以生产使用**：当前标记为 beta（`LangChainBetaWarning`）——文本/推理投影实测可用，但协议可能演进，生产建议 v2 为主。
2. **以为打字机效果就是 `print` 一下**：关键是 `end=""` + `flush=True`——缺一个就不像打字机。
3. **以为 reasoning tokens 所有模型都有**：只有支持且实际发出 reasoning 的模型/端点才有——本机实测（qwen3.8-flash + 百炼端点，简单问题）未产生独立 reasoning 流，用前先实测确认。

#### 一句话记住

> 打字机用 messages、进度条用 custom、思考过程用 reasoning——v3 事件流是未来，v2 是现在。

#### 🗣️ 行话对照

- **打字机效果 / typewriter effect**：逐 token 打印，模拟打字——在哪遇到：`stream_mode="messages"` + `print(end="", flush=True)`
- **reasoning tokens**：模型的思考过程 token——在哪遇到：`content_blocks` 中 `type="reasoning"` 的块
- **sub-agents**：被其他 agent 调用的 agent——在哪遇到：`create_agent(name="...")` + `subgraphs=True`
- **stream_events**：v3 事件流 API——在哪遇到：`agent.stream_events(version="v3")`
- **typed projections**：v3 中类型化的数据视图——在哪遇到：`stream.messages`、`stream.tool_calls`、`stream.values`

#### 官方文档

- [Streaming · Common patterns（打字机、reasoning、工具调用、HITL、子 agent）](https://docs.langchain.com/oss/python/langchain/streaming#common-patterns)
- [Event streaming（v3 协议、projections、sub-agents）](https://docs.langchain.com/oss/python/langchain/event-streaming)

---

## 第四幕：实操验证

回到第一幕：客服助手要"让转的过程实时可见"。以下五项验证全部本机跑通（脚本：`playground/lesson-06-streaming-lab.py`）：

1. **invoke vs stream 对照**：同一 agent、同一问题——invoke 2.8 秒无中间反馈；stream 在 1.4 秒即收到首 chunk（模型申请工具），总耗时相同（2.8 秒）——**stream 不改变执行速度，只改变反馈时机**。
2. **updates 模式**：3 个 chunk 对应 agent loop 三步（model → tools → model），每个 chunk 标注节点名、消息类型、tool_calls 状态——**agent 进度条的数据源**。
3. **messages 模式**：文本块逐块输出（本机 qwen3.8-flash 实测 5 个文本块 / 37 字；同期混有大量空增量 chunk——39 个 chunk 中 34 个为空）——**打字机效果的数据源**（务必判空）。
4. **custom 模式**：`get_stream_writer()` 在工具内发送"正在搜索…""已检索 3 条记录""搜索完成"信号——**工具进度条的数据源**。并行调用时信号交错（实测 3 次搜索进度混在一起）。
5. **v3 事件流**：`stream_events(version="v3")` 基本用法验证通过——`message.text` 为可迭代文本投影（逐块迭代）、`stream.output` 拿到最终状态；协议标记为 beta。

> ✅ **回扣场景**：第一幕的诉求全部有了着落——"用户盯空屏" = stream 首 chunk 1.4 秒即到（实测）；"不知道中间发生了什么" = updates 模式每步可见（实测）；"打字机效果" = messages 模式逐 token 输出（实测）；"工具进度" = custom 模式发信号（实测）。
>
> ⚠️ 数值说明：以上为 2026-09-15 本机实测；文本块粒度、chunk 数量（多次实测 21～80 个不等，其中多数为空增量）、首 chunk 延迟因模型与网络而异；v3 协议当前为 beta。

**应用实战（4.2）**：把本课知识点组装成一条「让用户看得见它在跑」的演进路线——独立成册：

> 🌊 **应用实战 6：让用户看见它在跑，而不是干等八秒** → [打开实战篇](../../../应用实战/06-Streaming流式输出.md)
>
> 从「invoke 等全部完成」到「stream 给进度与逐字」再到「业务进度信号 + 事件流」的三个版本演进：每一步解决了什么问题、还剩什么问题、下一步怎么被逼出来——配 3 张分步设计图（每张标注本步新增了什么）。

---

## 第五幕：体系收束

> 📍 **全局定位**：本课是阶段 2 的"体验层"——stream 让引擎的每一步从"内部黑盒"变成"外部可见"：
> - **课 7（Memory）**：流式 + 记忆 = 连续对话体验（每轮对话的流式输出 + 历史上下文）
> - **课 8（Middleware）**：流式 + 中间件 = 实时护栏（PII 脱敏中间件可在流式输出前拦截敏感内容）
> - **课 10（人机协同）**：流式 + 中断 = 审批进度可见（工具被中断时，流式能实时显示"等待审批"）
> - **前端集成**：v3 事件流可直接对接 `useStream` hook（React），实现流式 UI
>
> 🔗 **下一步**：课 7《Memory 记忆》——流式让过程可见，但 agent 还是"每次对话从零开始"，下一课给它装上"记忆"。

---

## 🐞 常见误区

1. **以为 stream 是"另一种调用"**：同一个 agent、同一条路——invoke 攒着给，stream 拆开给（实测总耗时完全一样）。
2. **以为"逐 token"就是"逐汉字"**：token 粒度由模型决定——本机 qwen3.8-flash 是"几个字一组"（实测 5 个 chunk 覆盖整句）。
3. **以为 v3 已经可以生产使用**：当前标记为 beta，API 行为可能与文档有差异（本机实测 `message.text` 返回完整文本而非迭代器）。
4. **以为 custom 信号会按工具调用顺序排列**：并行调用时信号交错（实测 3 次搜索的进度混在一起）。

### ⏳ 与过时说法对照（写前核对 + 实测发现的差异）

| 旧说法（网上教程 / 直觉） | 现状（官方文档 + 本课实测） | 依据 |
|---|---|---|
| "流式输出就是 `stream=True`" | LangChain 把流式从模型层提升到 agent 层——不只是 token 能流，每步状态、工具进度、自定义信号都能流 | streaming 页 + 实测 |
| "v2 和 v3 是同一套东西的不同版本号" | v2 是 LangGraph 底层协议（`stream()`），v3 是 LangChain 上层封装（`stream_events()`）——不同 API、不同设计理念 | streaming 页 + event-streaming 页 |
| "messages 模式的每个 chunk 都是一段内容" | 实测大多数 chunk 是空增量（多次采样：39 中 34、80 中 74 等）——打字机效果必须判空 | 实测 + 评审核查 |
| "流式输出会让 agent 跑得更快" | 总耗时不变（实测 2.8s）——只改变反馈时机，不改变执行速度 | 实测 1 段 |

## 一图总结

![流式三模式 + v3 事件流](../assets/lesson-06-summary.svg)

> 看图：三张卡片对应本课三站（流式的价值与机制 / 流模式全解 / 实战流式模式），第四张是"流式之后去哪"的衔接地图；底部是贯穿全课的链路——invoke（一次性）→ stream（逐步输出）→ 三种模式 + v3 事件流 → 前端 / 记忆 / 护栏。

## 课后小测

**Q1**：关于 `invoke` 和 `stream`，说法正确的是？
- A. stream 是另一种 API，走不同的执行路径
- B. stream 会让 agent 跑得更快
- C. 同一个 agent、同一次调用——invoke 攒着给结果，stream 拆开逐步给
- D. invoke 和 stream 不能用于同一个 agent

<details><summary>答案与解析</summary>

**答案：C**。本课实测：同一 agent、同一问题——invoke 和 stream 总耗时完全一样（2.8 秒），区别只在于 stream 在 1.4 秒就给出了首 chunk。A 错（同一条路），B 错（总耗时不变），D 错（同一个 agent 两种调用方式都支持）。

</details>

**Q2**：以下哪种场景最适合用 `stream_mode="custom"`？
- A. 做打字机效果（逐字输出）
- B. 显示 agent 当前执行到哪一步
- C. 在工具内部发送"正在搜索…""已找到 3 条记录"等进度信号
- D. 获取最终答案

<details><summary>答案与解析</summary>

**答案：C**。custom 模式专为工具/节点内的自定义信号设计——通过 `get_stream_writer()` 发送任意字符串。A 用 messages 模式，B 用 updates 模式，D 用 invoke 或 stream 的最后状态。

</details>

**Q3**：关于 v3 事件流（`stream_events`），当前版本的实际情况是？
- A. 已完全稳定，可以放心用于生产
- B. 标记为 beta（`LangChainBetaWarning`），API 行为可能与文档有差异
- C. 只能用于 async 代码
- D. 完全替代了 v2，v2 已废弃

<details><summary>答案与解析</summary>

**答案：B**。本机实测终端输出明确提示 `LangChainBetaWarning: The v3 streaming protocol on Pregel is experimental`——能力可用（文本/推理投影实测正常），但协议可能演进。A 错（beta），C 错（同步也支持），D 错（v2 仍是当前默认推荐）。

</details>

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课（无需重新描述上下文）：

```text
继续学 LangChain。我的学习档案在 langchain/langchain/00-学习档案.md，
刚学完阶段 2《Agent 核心》的课 6《Streaming 流式输出》全部知识点
（流式的价值与机制、流模式全解、实战流式模式），
请按大纲继续讲解课 7《Memory 记忆》的知识点。
```

## 🧭 课程导航

⬅️ **上一课**：[课 5：Agents 智能体核心](lesson-05-Agents智能体核心.md)

➡️ **下一课**：[课 7：Memory 记忆](lesson-07-Memory记忆.md)

📚 **返回目录**：[课程目录](../../../02-课程目录.md)

