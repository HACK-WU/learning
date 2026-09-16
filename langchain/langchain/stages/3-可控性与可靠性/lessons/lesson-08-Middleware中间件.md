# 第 8 课：Middleware 中间件（掌控 agent loop）

> 所属阶段：阶段 3《可控性与可靠性》｜ 水平：进阶（有扎实 Python 与后端工程基础，LangChain 从零）｜ 本课知识点：中间件机制、内置中间件、自定义中间件、组合与执行顺序
> 故事情节：引擎能跑、过程能看、记忆能存——但它"行为不受控"：出错就崩、没有刹车、敏感信息直通。本课给循环装上"可编程的刹车与方向盘"
> 📖 结论已按官方文档核对（核对于 2026-09 ｜ 来源：docs.langchain.com 的 middleware/overview、middleware/custom、middleware/built-in 三页；关键行为均经本机实测——脚本 `playground/lesson-08-middleware-lab.py`）

## 🎯 本课目标

- 说清中间件机制：agent loop 上有哪些钩子、能插入什么逻辑、为什么它是 1.x 的核心扩展方式（承接课 5 预告）
- 认识内置中间件全家：五组 19 个（容错 / 上下文 / 安全限制 / 工具增强 / 能力扩展）+ Provider 专属
- 能写自定义中间件：装饰器式与类式、state 读写、jump 提前收尾
- 掌握组合与执行顺序：before 正序、after 逆序、wrap 嵌套——以及顺序如何影响行为

---

## 第一幕：起源与场景引入

> 🏛️ **起源**：中间件（middleware）是软件工程的成熟模式——Web 框架（Express、Django 等）用它把"请求进、响应出"的管道切开，让鉴权、日志、限流这类横切逻辑层层插入而不侵入业务代码。LangChain 1.x 把同一思想引入 agent：把"模型调用、工具调用"看作管道中的步骤，**中间件包裹其上**——官方定位一句话："更紧密地控制 agent 内部发生的事"。课 5 里你已"用法级"见过它（`@wrap_model_call` 动态路由）；本课把机制、全家桶与组合规则一次展开（核对于 2026-09）。

客服助手第七次进化。现在它能跑（课 5）、过程能看（课 6）、记得住用户（课 7）——但生产上线的评审会上，你被一连串问题问住了：

**工具报错就崩**。第三方 API 抖一下，agent 直接中断（课 4 的实测结论：默认异常直接冒泡）。**没有刹车**。一个死循环的念头，就是一路烧钱。**敏感信息直通模型**。用户的手机号、邮箱原样送进第三方接口。**工具太多了**。20 个工具的说明书全塞进提示词，模型反而选错。

你想到的办法是"改源码"——但 `create_agent` 是官方封装，每加一个行为都要往里塞？不现实。

> 🎬 **场景**：官方其实在**循环上预留了一排插槽**——模型调用前、模型调用后、工具调用前后……你的逻辑挂进插槽，引擎照常转，行为全受控。这套插槽体系就叫**中间件**。

> 📌 **一句话本质**：中间件 = **agent 循环上的可编程钩子**。六个钩子挂在循环的各个步骤上（4 个"时刻式" + 2 个"包裹式"），通过 `create_agent(middleware=[...])` 声明；不改引擎源码，就能插入重试、限流、脱敏、审批、动态提示词等控制逻辑（核对于 2026-09）。
>
> ⚖️ **处境对照**：不这么写——工具报错直接崩（本课实测：`agent 中断：ValueError: 除数不能为 0`），敏感信息原样送达（无中间件时邮箱明文进模型），循环烧钱无上限。这么写——异常转成错误消息交给模型自愈（实测：模型收到"执行失败，请调整输入后重试"后给出得体答复），邮箱自动变 `[REDACTED_EMAIL]`，调用次数到达上限自动收尾（实测：`Model call limits exceeded: run limit (2/2)`）。

---

## 第二幕：认知冲突

第一次听到"给 agent 加一层控制"，很容易想到一个简单做法：**把 agent 包一层**——写个函数，invoke 之前检查一下、之后处理一下，不就行了？

这个理解是错的——或者说，只对了最外面一层。

**包在 agent 外面的函数，看不到"循环内部"**。agent 一次 invoke 里面可能转了好几圈：模型调用 1 → 工具 A → 模型调用 2 → 工具 B → 模型调用 3。你想"每次模型调用前检查一遍"、"每个工具失败后重试"——这些点都在**循环里面**，外面包一层根本够不着。

> ❓ **问题**：循环上有哪些标准插入点？插槽里能干什么活？多个插槽怎么排队？

三个追问把这件事拆开：

- 追问一：**循环上有哪些可插入点？**——模型调用前 / 模型调用后 / 工具调用前后 / agent 开始与结束时——官方定义了**六个钩子**（4 个"时刻式"节点钩子 + 2 个"包裹式"钩子）。课 7 用的 `@before_model` 裁剪、摘要中间件，就是其中两个钩子的应用（本课"归位"）。
- 追问二：**插槽里能干什么活？**——官方预置了 **19 个内置中间件**，覆盖容错、上下文、安全、工具增强、能力扩展五组；特殊需求再写自定义（课 5 六类能力地图与本课五组零件的对照，见知识点 2 全景表）。
- 追问三：**多个插槽怎么排队？**——before 类钩子**正序**、after 类**逆序**、wrap 类**嵌套**；顺序不只是"仪式感"，换位会**改变行为**（本课会用实测演示同一观察者看到 1 个 vs 6 个工具的差别）。

由此得到本课的第一个关键认知：**中间件的本质是"循环上的钩子集合"**——它不是一个外挂层，而是官方在引擎内部预留好、由你在编译期声明的插槽。理解"插槽都在哪、谁先谁后"，比记住 19 个零件名字更重要。

---

## 第三幕：层层揭示

### 一眼全局图（进入细节前先看一眼）

![从「改源码」到「插插槽」](../assets/lesson-08-overview.svg)

> 看图：左边是问题——加行为只能改源码？右边是本课方案——六个钩子的插槽体系 + 五组内置件 + 自定义 + 组合顺序；底部四张卡片对应本课四站。

### 本课地图（分几步走）

| 步 | 这一步要解决什么（人话） | 对应知识点 |
|:--:|------------------------|-----------|
| 1 | 循环上有哪些钩子、怎么声明中间件 | 知识点 1：中间件机制 |
| 2 | 19 个内置件各管什么（五组全景） | 知识点 2：内置中间件 |
| 3 | 特殊需求怎么自己写（装饰器/类/state/jump） | 知识点 3：自定义中间件 |
| 4 | 多个中间件怎么排队、顺序怎么影响行为 | 知识点 4：组合与执行顺序 |

### 知识点 1：中间件机制

> 🧭 第 1/4 步｜承接：课 5"用法级"露面的 `@wrap_model_call` 与六类能力地图 → 本步：展开钩子机制全貌

#### 一句话定义

中间件是在 agent 循环特定时刻被自动调用的**钩子集合**：官方定义六个钩子（`before_agent` / `before_model` / `after_model` / `after_agent` 四个节点式 + `wrap_model_call` / `wrap_tool_call` 两个包裹式），通过 `create_agent(middleware=[...])` 声明，用装饰器或类两种写法实现。

#### 直觉建立（类比）

快递分拣线上的"工位"：干线（agent 循环）固定不动，你可以在关键环节加装工位——**检查站**（节点式钩子：送到就查，顺序固定，做完放行）；**跟车师傅**（包裹式钩子：把下一段整个"包"在手里，叫几次、怎么叫由他定——重试就是"退回去再送一次"）。所有工位共用同一本"工单记录"（agent state）。

> 💡 **类比的边界**：工位不是旁路——工位就建在**分拣线内部**（钩子运行在同一条编译后的执行图里，本课实测图节点中可见中间件节点）；节点式钩子做完要"放行"（返回后继续原流程），包裹式钩子则**自己掌管下一步的调用时机**（可以不调、调一次或调多次）。

#### 核心原理

**① 六个钩子，两张表**（官方定义）：

| 节点式钩子（时刻式，顺序执行） | 何时运行 |
|------------------------------|----------|
| `before_agent` | agent 开始前（每次调用一次） |
| `before_model` | 每次模型调用前 |
| `after_model` | 每次模型响应后 |
| `after_agent` | agent 结束后（每次调用一次） |

| 包裹式钩子（包裹调用，控制执行） | 何时运行 |
|--------------------------------|----------|
| `wrap_model_call` | 包裹每次模型调用 |
| `wrap_tool_call` | 包裹每次工具调用 |

节点式适合日志、校验、状态更新；包裹式适合重试、缓存、变换——因为包裹式**决定内层调用几次**（0 次=短路、1 次=正常、多次=重试）。

**② 一次真实调用，钩子触发顺序**——本机实测（脚本 1a 段，一个带工具的完整调用）：

```text
【钩子】before_agent（每次调用一次）
【钩子】before_model（第 1 条消息已就位）
【钩子】wrap_model_call 进入 →（调用内层/模型）
【钩子】wrap_model_call 返回
【钩子】after_model（模型刚返回）
【钩子】wrap_tool_call 进入 → 即将执行工具 calculator
【钩子】wrap_tool_call 返回 ← 工具 calculator 完成
【钩子】before_model（第 3 条消息已就位）
【钩子】wrap_model_call 进入 →（调用内层/模型）
【钩子】wrap_model_call 返回
【钩子】after_model（模型刚返回）
【钩子】after_agent（agent 结束）
```

读法：`before_agent` 开局一次；进入循环后每一圈是「before_model →（模型）→ after_model」；模型申请工具时插入「wrap_tool_call →（工具）→ wrap_tool_call 返回」；工具结果回来再转一圈；最终以 `after_agent` 收尾。**钩子的位置，就是你能插手的位置**。

**③ 声明方式：装饰器式与类式两种写法**——装饰器式（适合单个钩子）：

```python
from langchain.agents.middleware import before_model, after_model, AgentState
from langgraph.runtime import Runtime
from typing import Any

@before_model
def log_before_model(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    print(f"About to call model with {len(state['messages'])} messages")
    return None

@after_model
def log_response(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    print(f"Model returned: {state['messages'][-1].content}")
    return None
```

类式（适合多个钩子/需要配置，本课实测的钩子全景就是这么写的）：

```python
from langchain.agents.middleware import AgentMiddleware

class HookTourMiddleware(AgentMiddleware):
    def before_agent(self, state, runtime):
        print("before_agent")
        return None
    def before_model(self, state, runtime):
        print("before_model")
        return None
    def wrap_model_call(self, request, handler):
        response = handler(request)
        return response
    # ... 其余钩子同理
```

两种写法效果等价；装饰器速写、类式组织。**中间件类还可以声明三个"编译期属性"**：`state_schema`（扩展 agent 状态）、`tools`（顺带注册工具，如待办清单的 `write_todos`）、`transformers`（注册流式转换器）。

**④ 钩子运行在编译后的图里，不是另一个运行时**——官方原话："Middleware is not a separate runtime: hooks run inside the compiled LangGraph that `create_agent` returns"。本机实测（结构核验，无模型调用）——给 agent 挂一个 `TodoListMiddleware` 后，编译图的节点列表：

```text
图节点: ['__start__', 'model', 'tools', 'TodoListMiddleware.after_model', '__end__']
```

中间件的钩子**以节点形态出现在同一张图里**——所以你能把整个 agent（连同全部中间件）当积木放进更大的工作流，钩子照样生效。同时实测：`TodoListMiddleware().tools` 注册的工具名为 `['write_todos']`——"中间件顺带注册工具"的机制眼见为实。

#### 示例演示

见上文实测：钩子触发顺序（②）、图节点（④），来源脚本 `playground/lesson-08-middleware-lab.py`（1a 段）与结构核验（无模型调用）。

#### 常见误区

1. **以为"包在 agent 外面"就行**：外面包一层够不着循环内部——每次模型调用、每次工具调用都在循环里，必须走钩子（本课六钩子全部"进"循环）。
2. **以为中间件是旁路外挂**：钩子运行在同一条编译图里（实测图节点可见）；它不能凭空改变引擎，只能在你声明它的位置插手。
3. **以为必须先学类式写法**：单个钩子用装饰器一行搞定；需要多钩子协同或配置参数时再升级到类式。

#### 一句话记住

> 不改引擎源码——在循环的六个插槽上，挂上你自己的逻辑。

#### 🗣️ 行话对照

- **middleware（中间件）**：循环上的钩子集合——在哪遇到：`create_agent(middleware=[...])`
- **节点式钩子（node-style hooks）**：before/after agent、before/after model——在哪遇到：装饰器或类方法
- **包裹式钩子（wrap-style hooks）**：wrap_model_call / wrap_tool_call——在哪遇到：`request` + `handler` 两个参数
- **handler**：包裹钩子里的"下一步调用入口"——在哪遇到：`handler(request)`；调几次由你定
- **state_schema / tools / transformers**：中间件类的三个编译期属性——在哪遇到：`AgentMiddleware` 子类
- **@dynamic_prompt**：动态系统提示词装饰器——在哪遇到：`langchain.agents.middleware`

#### 官方文档

- [Middleware overview（六钩子、图内运行、组合）](https://docs.langchain.com/oss/python/langchain/middleware/overview)
- [Custom middleware（写法、state、执行顺序、jump）](https://docs.langchain.com/oss/python/langchain/middleware/custom)

---

### 知识点 2：内置中间件

> 🧭 第 2/4 步｜承接：知道"插槽在哪、怎么插"了——现在就看看官方预置了哪些"标准件" → 本步：五组 19 个全景 + 五组实测代表

#### 一句话定义

内置中间件 = 官方预置的 19 个生产级组件（另加 Provider 专属若干），覆盖**容错、上下文管理、安全与限制、工具增强、能力扩展**五组；几乎每个常见控制需求都能"对号入座"（承接课 5 的六类能力地图）。

#### 直觉建立（类比）

官方把"循环上最常见的 19 种控制需求"做成了**标准件**，按五组装箱：容错箱（出错自愈）、上下文箱（历史管理）、安全箱（护栏与刹车）、工具增强箱（帮模型更好地用工具）、能力扩展箱（给 agent 加"手脚"，多为重型件）。多数场景不需要自己造件——先翻箱子。

> 💡 **类比的边界**：标准件不是"装了就万事大吉"——每个都要配参数（重试几次、限额多少、保留几条）；有些重型件来自附加包（`deepagents`），并不在 langchain 核心包里（本课会逐个标注归属与实测状态）。

#### 核心原理

**① 全景表：五组 19 个**（官方 built-in 页；与课 5 六类地图的对应关系一并在括号里）：

| 组 | 中间件 | 一句话 | 对应课 5 地图 |
|----|--------|--------|---------------|
| 容错 | Tool error | 工具异常转为错误消息，模型可自愈 | 容错 |
| 容错 | Tool retry | 工具失败自动重试（指数退避） | 容错 |
| 容错 | Model retry | 模型调用失败自动重试 | 容错 |
| 容错 | Model fallback | 主模型失联自动降级到备用模型 | 容错 |
| 上下文 | Summarization | 超阈值压缩历史（课 7 已实测，本课归位） | 上下文管理 |
| 上下文 | Context editing | 清理旧工具输出（保留最近 N 条） | 上下文管理 |
| 上下文 | To-do list | 给 agent 配备 `write_todos` 规划工具 | 规划与委派 |
| 安全 | Human-in-the-loop | 高危工具调用前暂停等人工审批（课 10 展开） | 引导 |
| 安全 | PII detection | 检测并处理个人信息（脱敏/掩码/阻断/哈希） | 护栏 |
| 安全 | Model call limit | 模型调用次数上限（防烧钱/防死循环） | 护栏 |
| 安全 | Tool call limit | 工具调用次数上限（可全局或单工具） | 护栏 |
| 工具增强 | LLM tool selector | 用 LLM 预选相关工具（工具多时提精度） | （新） |
| 工具增强 | Provider tool search | 把工具交给服务端按需检索（需模型支持） | （新） |
| 工具增强 | LLM tool emulator | 用 LLM 模拟工具执行（测试用） | （新） |
| 能力扩展 | Shell tool | 给 agent 一个持久 shell 会话 | 执行环境 |
| 能力扩展 | Filesystem | 文件读写工具（短期/长期记忆载体） | 执行环境 |
| 能力扩展 | Subagent | 派子 agent 干活（隔离上下文） | 规划与委派 |
| 能力扩展 | Rubric grading（beta） | LLM 评审官按评分标准迭代（自评自改） | （新） |
| 能力扩展 | File search | 提供 Glob/Grep 搜索工具 | 执行环境 |

另有 **Provider 专属**：Anthropic（提示词缓存、bash、文本编辑、记忆、文件搜索）、AWS（Bedrock 提示词缓存）、OpenAI（内容审核）——需要对应厂商模型，本课不实测。

**② 容错组：错误四件套的本机实测**——这组直接回应第一幕"工具报错就崩"的痛点：

先看**对照实验**（脚本 2d 段）——同一个会抛异常的工具，不加中间件 vs 加 `ToolErrorMiddleware`：

```text
  对照组（无中间件）：
    agent 中断：ValueError: 除数不能为 0
  实验组（ToolErrorMiddleware）：
  最终回答: 算不了 —— 10 除以 0 在数学上是**未定义**的。 刚才调用 `strict_divide(10, 0)` 时，工具按设计直接抛出了 `ValueError`，而不是返回一个数字。
  消息链:
    [0] human: 请算 10 除以 0。
    [1] ai → 调用工具: strict_divide({'a': 10, 'b': 0})
    [2] tool: `strict_divide` 执行失败（ValueError），请调整输入后重试。
    [3] ai: 算不了 —— 10 除以 0 在数学上是**未定义**的。
```

无中间件时异常**直接冒泡、agent 中断**（与课 4 结论一致）；挂上 `ToolErrorMiddleware(on_error=...)` 后，异常被转成**错误工具消息**（`status="error"`）交给模型——模型读懂后给出得体答复。官方还提醒：`on_error` 里**建议回类型名而不是原始异常文案**（原始文案可能带内部细节）；以及一个组合姿势——`ToolRetryMiddleware` 放**内层**（列表更前）并配 `on_failure="error"`，让"重试到耗尽"之后异常才冒到 `ToolErrorMiddleware` 手里。

再看**重试**（脚本 2c 段）——一个"前两次必故障、第三次成功"的工具，挂 `ToolRetryMiddleware(max_retries=3, initial_delay=0.05, backoff_factor=0.0, jitter=False)`：

```text
    （工具实际被执行：第 1 次）
    （工具实际被执行：第 2 次）
    （工具实际被执行：第 3 次）
  最终回答: 查询完成 ✅ 订单 **A100** 的结果为：**42**
  消息链:
    [2] tool: 查询成功：订单 A100 的结果 的结果是 42
```

工具被**实际执行 3 次**（2 败 1 成），模型侧只看到最终成功的结果——"重试"对其他环节完全透明。参数一句话版：`max_retries`（重试几次，默认 2）、`backoff_factor`/`initial_delay`/`max_delay`（退避节奏）、`jitter`（加随机抖动防"惊群"）、`retry_on`（重试哪些异常）、`on_failure`（耗尽后：`continue` 返回错误消息 / `error` 重新抛）。`ModelRetryMiddleware` 是模型侧的同款。

**降级**（脚本 2e 段）——给一个"模型名不存在"的主模型，挂 `ModelFallbackMiddleware(备用模型)`：

```text
  最终回答（来自降级模型）: 好
```

主模型失联（服务端报错），中间件自动切到备用模型完成回答——多供应商冗余的最简实现。

**③ 安全与限制组：两道"刹车"的实测**——先看**模型调用限额**（脚本 2a 段，`run_limit=2`、`exit_behavior="end"`）：

```text
  最终回答: Model call limits exceeded: run limit (2/2)
  消息链（注意最后一条）:
    [0] human: 先查北京天气，再查北京当前时间，最后给一句出行建议。
    [1] ai → 调用工具: get_weather({'city': '北京'})
    [2] tool: 北京：晴天，22°C
    [3] ai → 调用工具: get_time({'city': '北京'})
    [4] tool: 北京 当前时间 14:30
    [5] ai: Model call limits exceeded: run limit (2/2)
```

任务需要第 3 次模型调用（汇总建议）时额度耗尽——引擎**优雅收尾**：最后一条 AI 消息是限额说明（`exit_behavior="error"` 则改为直接抛异常）。`thread_limit`（跨整个会话）与 `run_limit`（单次 invoke）取其一或并用；`thread_limit` 需要 checkpointer 配合（跨轮计数）。

**工具调用限额**（脚本 2b 段，`tool_name="calculator", run_limit=1`）：

```text
  最终回答: 第一次计算器结果：**12 × 8 = 96**。 第二次调用时工具返回了“超过调用次数限制”，所以没有成功用计算器计算。手算结果是：**15 × 7 = 105**。
  消息链（注意被拦下的第二次调用）:
    [0] human: 请连续用计算器算两次：先算 12*8，再算 15*7。
    [1] ai → 调用工具: calculator({'expression': '12*8'}); calculator({'expression': '15*7'})
    [2] tool: Tool call limit exceeded. Do not call 'calculator' again.
    [3] tool: 12*8 = 96
    （[4] 为模型终答，内容见上方"最终回答"行）
```

一个值得注意的实测细节：模型把两次计算**放在同一条 AI 消息里并行申请**——限额放行了第一次、拦下第二次（错误消息 `Tool call limit exceeded...`），默认 `exit_behavior="continue"` 让 agent 继续跑，模型改用"心算"补上了第二次并如实说明。限额可以**全局**（不传 `tool_name`）或**单工具**，两种写法实测均按预期生效。

**PII 脱敏**（脚本 2f 段）——`PIIMiddleware("email", strategy="redact")` + `PIIMiddleware("credit_card", strategy="mask")`：

```text
  最终回答: 邮箱 [REDACTED_EMAIL]，卡号 **** **** **** 1111。
```

模型回复里复述出的正是**脱敏后**的文本——说明敏感的原文**没有**送进模型（模型只见到替换后的形式）。四种策略：`redact`（替换为 `[REDACTED_类型]`）/ `mask`（部分打码）/ `hash`（确定性哈希）/ `block`（直接抛异常阻断）。内置类型有 `email`、`credit_card`、`ip`、`mac_address`、`url`；不够用可自定义检测器（正则字符串 / 编译后正则 / 自定义函数三选一）。检查方向可分别开关：`apply_to_input`（默认开）、`apply_to_output`、`apply_to_tool_results`。

**④ 工具增强组：选择器实测**（脚本 2g 段，6 个工具、`max_tools=2`）——拿到"北京天气"问题后，选择器先让 LLM 预选工具，实际调用链只有 `get_weather`：

```text
    [1] ai → 调用工具: get_weather({'city': '北京'})
```

更硬的证据在知识点 4（顺序换位实验）：同一批 6 个工具，经过选择器后模型只见 **1 个**（`['get_weather']`）；不经过选择器则见全部 **6 个**。选中的工具名、`always_include`（永远保留的工具）、`max_tools` 上限都可配；官方还标注它用结构化输出实现——**每次多一次选择模型调用**（工具多、提示词长的场景才回本）。同组的 `Provider tool search` 把筛选放到模型服务端（需 Anthropic/OpenAI 特定模型支持，本机环境不适用、未实测）；`LLM tool emulator` 用 LLM 假扮工具执行——集成测试时的"替身演员"。

**⑤ 上下文组与规划：待办清单实测**（脚本 2h 段）——`TodoListMiddleware()` 给 agent 注册 `write_todos` 工具（实测注册名 `['write_todos']`）。它的行为有一处**需要如实说明的观察**：

- 3 步简单任务：模型**未**调用 `write_todos`（直接并行调用两个工具搞定）。
- 5 步带决策依赖任务：模型**仍未**主动调用（直接逐步执行）。
- 只有**用户明确要求**"先用待办清单列出计划"时，才出现完整闭环：

```text
    [1] ai → 调用工具: write_todos({'todos': [{'content': '第一步：查询北京天气', 'status': 'in_progress'}, {'content': '第二步：查询北京当前时间', 'status': 'in_progress'}, {'content': '第三步：汇总天气和时间，给出一句出行建议', 'status': 'pending'}]})
    [2] tool: Updated todo list to [{'content': '第一步：查询北京天气', 'status': 'in_progress'},
    [3] ai → 调用工具: get_weather({'city': '北京'})
    [3] ai → 调用工具: get_time({'city': '北京'})
    [6] ai → 调用工具: write_todos({'todos': [{'content': '第一步：查询北京天气', 'status': 'completed'}, {'content': '第二步：查询北京当前时间', 'status': 'completed'}, {'content': '第三步：汇总天气和时间，给出一句出行建议', 'status': 'completed'}]})
    [7] tool: Updated todo list to [{'content': '第一步：查询北京天气', 'status': 'completed'},
    [8] ai: 任务已全部完成，汇报如下： **查询结果** - 北京天气：晴天，22°C - 北京当前时间：14:30
    （[0] 为任务输入、[4][5] 为两个查询工具的回执，此处为节选展示）
```

原因在工具自带的说明书里：`write_todos` 的描述写明"若任务少于 3 个步骤且直接可做，**最好别用**这个工具"——本机模型（qwen3.8-flash）确实按此指引**自行判断**了两次。所以对这套中间件的正确期待是：它提供**能力与使用指引**，但**不强制**规划；要在关键场景确保被用，需要在系统提示词里明确要求（或结合课 9 的上下文工程）。同组的 `SummarizationMiddleware` 课 7 已详测（此处归位）；`ContextEditingMiddleware` 专清"旧的工具输出"（保留最近 N 条、按 token 阈值触发）——本机未实测，按官方口径标注。

**⑥ 能力扩展组：整体标注**——`ShellToolMiddleware`（持久 shell，注意执行策略与安全红线）、`FilesystemMiddleware`（官方来源为 `deepagents` 包，含 ls/read/write/edit 四工具，可后端配 State/Store 实现短期/长期记忆）、`SubAgentMiddleware`（派子 agent，隔离上下文）、`RubricMiddleware`（beta，自评迭代）、`FilesystemFileSearchMiddleware`（Glob/Grep 搜索）——这些属于"给 agent 加手脚"的重型件，多数来自 `deepagents` 附加包；本课**未实测**（按官方口径收录，用到再深挖）。

#### 示例演示

见上文实测：容错四件套（②）、限额两闸门与 PII（③）、工具选择器（④）、待办清单（⑤），来源脚本 `playground/lesson-08-middleware-lab.py`（2a-2h 段）；能力扩展组为官方归纳（未实测，已标注）。

#### 常见误区

1. **以为"工具报错会被引擎自动兜住"**：默认不兜——实测直接中断（2d 对照），要兜就挂 `ToolErrorMiddleware`（或课 4 的自定义包裹钩子）。
2. **以为限额是"到了就抛错"**：默认行为可配——`continue`（拦下超额调用、让 agent 继续）或 `end`（优雅收尾）或 `error`（抛异常）；实测两者均按预期。
3. **以为挂了待办清单就会自动规划**：实测两次自主跳过——它提供能力+指引，`用不用`由模型按任务复杂度判断（描述里明确写了"少于 3 步别用"）。
4. **以为重试是"零成本"**：工具被真实执行多次（实测 3 次）——对幂等/无副作用的工具才可放心重试，写操作要配 `max_retries` 与去重设计。

#### 一句话记住

> 先翻箱子再造件：容错、上下文、安全、工具增强、能力扩展——五组 19 个标准件，覆盖绝大多数控制需求。

#### 🗣️ 行话对照

- **ToolErrorMiddleware / ToolRetryMiddleware**：工具异常兜底 / 工具重试——在哪遇到：`langchain.agents.middleware`
- **ModelFallbackMiddleware**：模型降级——在哪遇到：主模型后接备用模型列表
- **run_limit / thread_limit**：单次调用 / 跨会话的限额——在哪遇到：Model/Tool call limit
- **on_failure**：重试耗尽后的行为（continue/error）——在哪遇到：重试类中间件
- **PIIMiddleware / strategy**：个人信息中间件 / 处理策略（redact/mask/hash/block）——在哪遇到：安全组
- **write_todos**：待办清单工具（由 TodoListMiddleware 注册）——在哪遇到：工具列表自动多出一个

#### 官方文档

- [Built-in middleware（五组 19 个 + Provider 专属全集）](https://docs.langchain.com/oss/python/langchain/middleware/built-in)
- [Built-in · Summarization / HITL / Limits / PII 各段落](https://docs.langchain.com/oss/python/langchain/middleware/built-in#provider-agnostic-middleware)

---

### 知识点 3：自定义中间件

> 🧭 第 3/4 步｜承接：标准件翻完了——没有合用的怎么办？ → 本步：装饰器式与类式两把工具 + state 读写 + jump 提前收尾

#### 一句话定义

自定义中间件 = 按需实现六个钩子中的任意几个：装饰器式适合单钩子速写，类式适合多钩子协同与配置；状态更新在节点式钩子里**返回 dict**、在包裹式钩子里**返回 `Command`**；声明 `can_jump_to` 后可用 `jump_to` **提前收尾**。

#### 直觉建立（类比）

标准件是"预制菜"，自定义是"开小灶"：食材还是那批（六个钩子），但配方由你定——**装饰器**像"单菜品快炒"（一个函数一道菜），**类**像"套餐厨房"（多个钩子 + 配置 + 可以带自己的状态字段和工具）。"提前收尾"则是出餐口的"一键打烊"：还没做完全部工序？判断不需要了，直接跳到收拾环节。

> 💡 **类比的边界**：小灶也得守厨房纪律——节点式钩子只管"返回什么改什么"（返回 `None` 表示不改），包裹式钩子则必须**显式调用 `handler`** 才会继续（不调=短路，调两次=重试——这也是官方内置重试件的原理）。

#### 核心原理

**① 装饰器式：单钩子速写**——本机实测（脚本 3a 段）：两个装饰器中间件协同，一个计数、一个打日志，用**自定义 state 字段** `model_call_count` 跨步传递：

```python
class CounterState(AgentState):
    model_call_count: NotRequired[int]

@before_model(state_schema=CounterState)
def log_before(state: CounterState, runtime):
    print(f"[自定义] before_model：即将进行第 {state.get('model_call_count', 0) + 1} 次模型调用")
    return None

@after_model(state_schema=CounterState)
def count_after(state: CounterState, runtime):
    c = state.get("model_call_count", 0) + 1
    print(f"[自定义] after_model：模型调用计数 → {c}")
    return {"model_call_count": c}
```

实测输出（一次带工具的调用，两圈循环）：

```text
  [自定义] before_model：即将进行第 1 次模型调用
  [自定义] after_model：模型调用计数 → 1
  [自定义] before_model：即将进行第 2 次模型调用
  [自定义] after_model：模型调用计数 → 2
  最终状态里的计数 model_call_count = 2
```

三个要点：**装饰器要带 `state_schema=`**（声明这个钩子参与哪个状态形状）；**返回 dict 即更新状态**（`after_model` 返回 `{"model_call_count": c}`，走图的归约器合并；返回 `None` 表示不动）；**计数跨步保持**（最终 invoke 返回值里 `model_call_count = 2`）——这就是"自定义 state 在循环中读写"的完整闭环。

**② 类式：多钩子组织**——知识点 1 的"钩子全景"就是类式（`class HookTourMiddleware(AgentMiddleware)`），把六个钩子写在同一个类里。类的三个"编译期属性"（官方）：`state_schema`（等价于装饰器的 `state_schema=`）、`tools`（顺带注册工具，如待办清单）、`transformers`（注册流式转换器，需 langchain>=1.3.2）。选型口诀：**单钩子用装饰器，多钩子/要配置/要复用用类**。

**③ 包裹式钩子的状态更新：走 `Command`**（官方）——包裹钩子里没有"直接返回 dict"这条路：模型侧要返回 `ExtendedModelResponse(model_response=..., command=Command(update={...}))`，工具侧直接返回 `Command`。多中间件同时更新时的合成规则（官方）：命令**每个都经归约器应用**（消息是追加式）；非归约器字段**外层赢**（conflicts 时 outermost 优先）；外层若重试导致多次调用，**早先调用的命令被丢弃**（retry-safe）。

**④ jump_to：提前收尾**——本机实测（脚本 3b 段）：一个"内容守护"中间件，检测到触发词就跳过模型、直接给兜底回复并结束：

```python
@before_model(can_jump_to=["end"])
def content_guard(state, runtime):
    last = state["messages"][-1]
    if "禁止话题" in str(last.content):
        return {
            "messages": [AIMessage("抱歉，这个话题我不能处理。")],
            "jump_to": "end",
        }
    return None
```

实测两个场景：正常输入照常走模型（"你好！"）；触发词输入被**直接拦下**——

```text
  场景二（触发守护）：
  [守护] 检测到敏感输入，跳过模型直接收尾
  最终回答: 抱歉，这个话题我不能处理。
  消息数（应为 2：输入 + 兜底回复，无模型输出）: 2
    [0] human: 我们来聊禁止话题吧。
    [1] ai: 抱歉，这个话题我不能处理。
```

消息链只有"用户输入 + 兜底回复"两条（没有模型输出）——跳转**省掉了这次模型调用**。三个跳转目标（官方）：`'end'`（跳到结束/第一个 after_agent）、`'tools'`、`'model'`；能跳的方向要用 `can_jump_to=[...]`（类式配 `@hook_config(can_jump_to=[...])`）**先声明**——声明是安全设计：引擎据此把图编译成允许跳转的形态。

#### 示例演示

见上文实测：计数 + state（①）、jump 守护（④），来源脚本 `playground/lesson-08-middleware-lab.py`（3a、3b 段）。

#### 常见误区

1. **以为消息要自己"拼回去"**：节点式钩子返回的 dict 经默认归约器合并——消息是**追加**语义，不用手动重排（要删改才用课 7 的 `RemoveMessage` 手法）。
2. **以为 `jump_to` 随手可用**：需要先 `can_jump_to` 声明（官方示例里装饰器参数、类式的 `@hook_config`）；未声明就跳会被状态 schema 拒绝。
3. **以为 `state_schema=` 可省**：不对——装饰器模式要显式带上，否则该字段/自定义状态不生效（官方示例与实测均如此写）。

#### 一句话记住

> 装饰器速写单钩子、类式组织多钩子；状态更新节点式返 dict、包裹式走 Command；提前收尾先声明 can_jump_to。

#### 🗣️ 行话对照

- **state_schema / CustomState**：自定义状态形状——在哪遇到：装饰器参数、`AgentState` 子类
- **can_jump_to / jump_to**：跳转许可声明 / 跳转指令——在哪遇到：装饰器参数、`@hook_config`、返回 dict
- **ExtendedModelResponse**：包裹模型钩子的带命令返回——在哪遇到：`wrap_model_call` 内
- **hook_config**：类式钩子的配置装饰器——在哪遇到：`@hook_config(can_jump_to=[...])`
- **reduce / 归约器**：状态合并规则（如 add_messages）——在哪遇到：自定义状态字段设计

#### 官方文档

- [Custom middleware · State updates（dict vs Command）](https://docs.langchain.com/oss/python/langchain/middleware/custom#state-updates)
- [Custom middleware · Agent jumps（jump_to 与 can_jump_to）](https://docs.langchain.com/oss/python/langchain/middleware/custom#agent-jumps)

---

### 知识点 4：组合与执行顺序

> 🧭 第 4/4 步｜承接：会写中间件了——多个中间件同时挂上，谁先谁后？ → 本步：三条顺序规则 + 换位实测 + 实用规则

#### 一句话定义

多中间件按固定规则协作：**before 类钩子正序执行**（列表顺序）、**after 类钩子逆序执行**（反序）、**wrap 类钩子嵌套**（第一个在最外层，像函数调用栈）；顺序不是形式主义——换位会**实际改变行为**。

#### 直觉建立（类比）

套娃：你要把三个玩偶（M1、M2、M3）装进一个箱子里——**进门时**按 M1→M2→M3 顺序摆放（before 正序）；**出门时**倒着碰到 M3→M2→M1（after 逆序）；**包裹式**像三层包装纸：M1 包着 M2、M2 包着 M3、M3 贴着货物——打开时从外到内，复原时从内到外。

> 💡 **类比的边界**：套娃是静态的，钩子是动态的——包裹层还能"决定里面拆不拆、拆几次"（重试/短路），这是套娃没有的权力；这也是"关键中间件放外层还是内层"如此重要的原因。

#### 核心原理

**① 顺序规则与实测**——官方三条规则：`before_*` 正序、`after_*` 逆序、`wrap_*` 嵌套。本机实测（脚本 4a 段，M1/M2/M3 三个全钩子中间件；该次调用模型直接作答、未走工具，故先看 agent 层与模型层的完整顺序）：

```text
  [M1] before_agent
  [M2] before_agent
  [M3] before_agent
  [M1] before_model
  [M2] before_model
  [M3] before_model
  [M1] wrap_model_call 进入
  [M2] wrap_model_call 进入
  [M3] wrap_model_call 进入
  [M3] wrap_model_call 返回
  [M2] wrap_model_call 返回
  [M1] wrap_model_call 返回
  [M3] after_model
  [M2] after_model
  [M1] after_model
  [M3] after_agent
  [M2] after_agent
  [M1] after_agent
```

工具被真实调用时，工具圈的包裹顺序（4a 补测段：大数乘法强制走工具）：

```text
  [M1] wrap_tool_call 进入
  [M2] wrap_tool_call 进入
  [M3] wrap_tool_call 进入
  [M3] wrap_tool_call 返回
  [M2] wrap_tool_call 返回
  [M1] wrap_tool_call 返回
```

三条规则在真实运行中逐条应验：进场正序、出场逆序、包裹嵌套。

**② 顺序影响行为：换位实测**——脚本 4b 段：同一个"观察者"中间件（打印模型可见的工具清单）与同一个"工具选择器"（把 6 个工具筛到 ≤2 个），只交换两者在列表里的位置：

```text
  顺序 A：selector 在前（外层），观察者在后（内层）
  [观察者] 模型可见工具（1 个）: ['get_weather']
  顺序 B：观察者在前（外层），selector 在后（内层）
  [观察者] 模型可见工具（6 个）: ['get_weather', 'translate_text', 'tell_joke', 'unit_convert', 'book_flight', 'get_time']
```

同一个观察者：外层时看到**全部 6 个**（选择器还没动手），内层时看到**过滤后的 1 个**。这就是"wrap 嵌套"的实际含义——**外层的修改先发生，内层看到的是已被外层改过的请求**（这也解释了课 5 动态模型路由为什么一个 `@wrap_model_call` 就能全局换模型）。官方还能佐证：多个中间件同时注入状态时"外层赢"的规则、以及重试在外层则"早先调用的命令被丢弃"——都是同一条嵌套语义的推论。

**③ 一个实测到的边界**：**同类中间件默认同名，不能挂两个**——首跑时挂三个 `OrderMiddleware` 实例被引擎拒绝：

```text
AssertionError: Please remove duplicate middleware instances.
```

原因是 `AgentMiddleware.name` 默认取**类名**，引擎启动时按 name 判重（源码：`len({m.name for m in middleware}) != len(middleware)` 即报错）。解决：让每个实例有唯一 name（本课实测通过 `@property name` 返回 `f"order-{tag}"` 修复）。对使用者的意义：**同一中间件类要实例化多份时（不同参数的限额、不同目标的观察者），记得给实例起名**。

**④ 实用规则**（官方 best practices 摘编 + 实测印证）：

- 每个中间件**只做一件事**（单一职责——否则顺序调试会变成噩梦）；
- 让中间件**优雅处理错误**，别让它自己的异常崩掉 agent；
- 选对钩子类型：**顺序逻辑用节点式**（日志、校验），**控制流用包裹式**（重试、降级、缓存——它们要"决定调几次"）；
- **关键中间件放前面**（外层）——外层先改请求、先拦错误（4b 已证明顺序即行为）；
- 自定义 state 要**写清文档**；中间件**先单测再集成**；
- **优先用内置**（19 个标准件覆盖大多数场景）。

#### 示例演示

见上文实测：三中间件顺序（①）、换位对照（②）、同类判重（③），来源脚本 `playground/lesson-08-middleware-lab.py`（4a/4b 段）与续跑/补跑脚本（见 temp 留档）。

#### 常见误区

1. **以为顺序只是"打印差异"**：顺序即行为——4b 中同一观察者看到 1 个 vs 6 个工具，这就是"外层先改、内层后见"的直接后果。
2. **以为两个同类实例可以直接挂**：默认同名被拒（实测 AssertionError）——用 name 区分（或换不同类）。
3. **以为重试放哪层都一样**：放外层时内层被重跑、早先命令丢弃（官方 retry-safe 规则）；想"重试到耗尽再交错误兜底"，要按官方姿势把 retry 放内层、error 兜底放外层。

#### 一句话记住

> 进场正序、出场逆序、包裹嵌套——顺序表就是行为表；外层先动手，内层见结果。

#### 🗣️ 行话对照

- **执行顺序（execution order）**：before 正序 / after 逆序 / wrap 嵌套——在哪遇到：多中间件列表
- **name 判重**：同类实例需要唯一名称——在哪遇到：`AgentMiddleware.name` 属性
- **outer wins / retry-safe**：包裹式命令的合成规则——在哪遇到：官方 custom middleware 页

#### 官方文档

- [Custom middleware · Execution order（三条规则）](https://docs.langchain.com/oss/python/langchain/middleware/custom#execution-order)
- [Custom middleware · Best practices](https://docs.langchain.com/oss/python/langchain/middleware/custom#best-practices)

---

## 第四幕：实操验证

回到第一幕：评审会上的四个问题，逐一有了着落。以下六组验证全部本机跑通（脚本：`playground/lesson-08-middleware-lab.py` + 续跑/补跑脚本）：

1. **钩子机制（1a）**：单中间件全钩子触发顺序完整捕获（before_agent → 循环内 model/tool 钩子交替 → after_agent）；编译图节点实测含中间件节点（`TodoListMiddleware.after_model`）。
2. **容错四件套（2c-2e）**：重试 3 次成功（对模型透明）；错误兜底对照（默认崩 vs 转错误消息自愈）；模型降级（坏模型名 → 备用模型完成回答）。
3. **限额两道闸门（2a/2b）**：模型限额优雅收尾（`Model call limits exceeded: run limit (2/2)`）；工具限额拦下并行调用中的超额项（`Tool call limit exceeded...`），模型继续并如实说明。
4. **PII 脱敏（2f）**：邮箱 `[REDACTED_EMAIL]` + 卡号掩码（`**** **** **** 1111`）——原文未进模型。
5. **工具选择器与待办清单（2g/2h）**：6 工具筛到 1 个（选择器）；待办清单注册 `write_todos`、明确要求后完整闭环（建模版 → 执行 → 更新 → 汇报），自主跳过两次的原因出自工具自带指引（"少于 3 步别用"）。
6. **自定义与顺序（3a/3b/4a/4b）**：计数 state 跨步保持（最终 `model_call_count = 2`）；jump 守护跳过模型（消息数 2）；三中间件顺序三条规则应验；换位对照（1 个 vs 6 个工具）；同类判重与 name 修复。

> ✅ **回扣场景**：第一幕四个痛点全部有解——"工具报错就崩" = ToolErrorMiddleware（2d）；"没有刹车" = 两道限额（2a/2b）；"敏感信息直通" = PIIMiddleware（2f）；"工具太多选错" = LLMToolSelectorMiddleware（2g）。而且全部**不改引擎源码**——插槽体系兑现了承诺。
>
> ⚠️ 数值说明：以上为 2026-09-15 本机实测；限额与重试行为取决于配置参数（重试次数、退避设置），本课为演示取了小值；模型回答措辞受采样影响（对照实验的行为差异——崩溃/继续、1 个/6 个工具——为机制性差异，非措辞浮动）；能力扩展组与 Provider 专属未实测（已标注）。

---

## 第五幕：体系收束

> 📍 **全局定位**：本课是阶段 3《可控性与可靠性》的**开篇**——"能跑、能看、能记"之后，进入"受控"：
> - **课 9（Context Engineering）**：中间件是"往模型上下文里放什么"的执行者——课 9 系统化上下文策略（本课的 state、动态提示词都将在那里归位）
> - **课 10（人机协同与护栏）**：`HumanInTheLoopMiddleware` 深展开（中断、审批、恢复），与本课的安全组直接接力
> - **课 11（Retrieval 检索与 RAG）**：工具选择器/工具检索与知识检索同源（"该给模型看什么"）
> - **回看主线**：课 1 的 "Agent = Model + Harness"——中间件是 harness 的**可编程控制层**，六类能力地图（课 5）在此有了完整实现
>
> 🔗 **下一步**：课 9《Context Engineering 上下文工程》——从"控制行为"走向"管理输入"：模型的上下文窗口里，究竟该放什么、何时放、放多少。

---

## 🐞 常见误区

1. **以为"包在 agent 外面"能替代中间件**：循环内部的每一步只有钩子够得着（六个钩子全部"进"循环）。
2. **以为工具异常会默认被兜住**：默认直接崩（实测 2d 对照）——兜底要显式挂件。
3. **以为限额到顶就抛错**：行为可配（continue/end/error），默认拦下超额项让 agent 继续（2b/2a 实测两种姿态）。
4. **以为顺序无所谓**：4b 换位实测——同一观察者看到 1 个 vs 6 个工具。
5. **以为同类中间件可以随便挂多个**：默认同名判重（实测 AssertionError），要起唯一 name。

### ⏳ 与过时说法对照（写前核对 + 实测发现的差异）

| 旧说法（网上教程 / 直觉） | 现状（官方文档 + 本课实测） | 依据 |
|---|---|---|
| "给 agent 加控制逻辑 = 改 create_agent 源码" | 官方在循环上预留六个钩子，`middleware=[...]` 即插即用 | overview + 全部实测 |
| "工具报错会被引擎自动转成消息" | 默认异常冒泡、agent 中断；要兜底需 ToolErrorMiddleware（或自定义包裹钩子） | 2d 对照 |
| "重试/限额这类优化是免费的" | 工具被真实多次执行；限额改变控制流；行为都要按参数与场景选择 | 2c、2a、2b |
| "挂了待办清单 agent 就会自动规划" | 本机模型两次自主跳过（按工具指引判断"不需要"）；明确要求后完整闭环 | 2h 三段观察 |
| "中间件顺序不影响结果" | 顺序即行为：外层先改请求、内层见结果（1 个 vs 6 个工具） | 4b 换位 |
| "多个同参数中间件直接挂就行" | 默认同名判重报错，需 name 区分 | 4a 首跑 AssertionError |
| "中间件是外挂旁路，与执行图无关" | 钩子运行在编译后的同一张图（图节点实测可见） | 结构核验 |

## 一图总结

![六个钩子与四站](../assets/lesson-08-summary.svg)

> 看图：四张卡片对应本课四站（机制 / 内置 / 自定义 / 组合顺序），底部链路——agent loop → 六个插槽 → 内置+自定义 → 组合规则，以及通往课 9（上下文工程）与课 10（HITL）的下一站。

## 课后小测

**Q1**：关于中间件的钩子，说法正确的是？
- A. 六种钩子都运行在 agent 的外层（invoke 前后）
- B. 四个节点式钩子按"时刻"触发（before/after agent/model），两个包裹式钩子会调 handler 若干次（可不调/一次/多次）
- C. 只有继承 `AgentMiddleware` 类才能写中间件
- D. 钩子运行在独立的"中间件运行时"里，与 agent 的执行图无关

<details><summary>答案与解析</summary>

**答案：B**。A 错——六个钩子都在循环里（每圈模型/工具调用都会触发，实测 1a）；C 错——装饰器即可（3a 实测）；D 错——官方明确"hooks run inside the compiled LangGraph"，本课实测图节点里可见中间件节点。

</details>

**Q2**：关于"给 agent 加容错"，说法正确的是？
- A. 工具抛异常时引擎默认会把异常转成错误消息
- B. `ToolRetryMiddleware` 只影响给模型的输出，工具实际只执行一次
- C. 默认工具异常直接冒泡中断 agent；`ToolErrorMiddleware` 可把异常转成错误消息，重试则要 ToolRetryMiddleware（可组合）
- D. Model fallback 用于工具调用失败

<details><summary>答案与解析</summary>

**答案：C**。A 错——本课 2d 对照：无中间件时 `agent 中断：ValueError`；B 错——实测工具被真实执行 3 次（2c）；D 错——fallback 是模型侧（2e：坏模型 → 备用模型）。

</details>

**Q3**：关于多个中间件的执行顺序与组合，说法正确的是？
- A. before 与 after 钩子都按列表正序执行
- B. wrap 钩子按列表顺序串行执行，互不影响
- C. before 正序、after 逆序、wrap 嵌套；换位会实际改变行为（实测同一观察者可见 1 个 vs 6 个工具）
- D. 两个同类中间件实例可直接同时挂载

<details><summary>答案与解析</summary>

**答案：C**。A 错——after 是逆序（4a 实测 M3→M2→M1）；B 错——wrap 是嵌套（M1 包 M2 包 M3），外层先改请求；D 错——默认同名判重会报 AssertionError（4a 首跑实测），需 name 区分。

</details>

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课（无需重新描述上下文）：

```text
继续学 LangChain。我的学习档案在 langchain/langchain/00-学习档案.md，
刚学完阶段 3《可控性与可靠性》的课 8《Middleware 中间件》全部知识点
（中间件机制、内置中间件、自定义中间件、组合与执行顺序），
请按大纲继续讲解课 9《Context Engineering 上下文工程》的知识点。
```

## 🧭 课程导航

⬅️ **上一课**：[课 7：Memory 记忆](../../2-Agent核心/lessons/lesson-07-Memory记忆.md)

➡️ **下一课**：[课 9：Context Engineering 上下文工程](lesson-09-ContextEngineering上下文工程.md)

📚 **返回目录**：[课程目录](../../../02-课程目录.md)

