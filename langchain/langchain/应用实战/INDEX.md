# 应用实战 · 总索引

> 每课一篇应用实战：跟着作者走一遍「从幼稚到像样」的演进，把知识点焊进真实用法。
> 已编写 = 可点击链接；未编写 = 纯文本。
> 说明：应用实战按 topic-teach「判定三问」配套（场景可得 / 演进 ≥2 跳 / 非硬凑）——**不配是常态，不是缺漏**；索引随课程进度更新。

## 阶段 1：入门与模型层

### [实战 2：给模型接入加一道「主备保险」](02-Models模型层.md)

- 配套课程：[课 2《Models 模型层》](../stages/1-入门与模型层/lessons/lesson-02-Models模型层.md)
- 场景：模型单点故障——从「单模型硬编码」到「主备降级 + 配置化 + 能力门禁」
- 覆盖知识点：init_chat_model 接入 / with_fallbacks 降级 / profile 能力探测与手动覆写
- 演进步：第 1 版 单模型硬编码 → 第 2 版 主备降级 → 第 3 版 配置化与能力门禁（每步配分步设计图）

### [实战 3：把多轮对话历史存下来并能回放](03-Messages消息体系.md)

- 配套课程：[课 3《Messages 消息体系》](../stages/1-入门与模型层/lessons/lesson-03-Messages消息体系.md)
- 场景：内存里的对话一刷新就失忆——从「字符串拼接历史」到「序列化落库 + 安全回放」
- 覆盖知识点：四类消息与角色 / 多模态 content blocks / dumpd 与 load 序列化
- 演进步：第 1 版 字符串拼接 → 第 2 版 标准消息对象 → 第 3 版 序列化落库与回放（每步配分步设计图）

### 实战 1（未配）

- **课 1《LangChain 是什么》判定不配**：导论 + 起源 + 版本演进课，凑不出「基础实现 → 它的问题 → 综合实现」两跳演进，硬配会退化成概念复述。

## 阶段 2：Agent 核心

### [实战 4：把内部订单 API 变成 agent 敢用的工具](04-Tools工具.md)

- 配套课程：[课 4《Tools 工具》](../stages/2-Agent核心/lessons/lesson-04-Tools工具.md)
- 场景：裸函数当工具——从「契约靠猜、出错即崩」到「结构化契约 + 异常转译 + 按角色准入」
- 覆盖知识点：@tool 与 args_schema / Pydantic 校验 / wrap_tool_call 异常转译 / 注册表式工具选择
- 演进步：第 1 版 裸函数当工具 → 第 2 版 结构化契约与异常转译 → 第 3 版 按角色装配工具集（每步配分步设计图）

### [实战 5：让客服 agent 跑得可控、结果可接、过程可见](05-Agents智能体核心.md)

- 配套课程：[课 5《Agents 智能体核心》](../stages/2-Agent核心/lessons/lesson-05-Agents智能体核心.md)
- 场景：默认配置一把梭——从「步数无上限、结果不可编程」到「护栏 + 结构化输出 + 流式与账本」
- 覆盖知识点：create_agent 配置 / agent loop 返回解读 / response_format 结构化输出 / stream 三种模式
- 演进步：第 1 版 默认配置一把梭 → 第 2 版 加护栏与结构化输出 → 第 3 版 流式进度与运行账本（每步配分步设计图）

### [实战 6：让用户看见它在跑，而不是干等八秒](06-Streaming流式输出.md)

- 配套课程：[课 6《Streaming 流式输出》](../stages/2-Agent核心/lessons/lesson-06-Streaming流式输出.md)
- 场景：非流式盲等——从「等全部完成才输出」到「stream 传输 + 业务进度信号 + 事件流聚合」
- 覆盖知识点：stream 与 stream_mode / get_stream_writer 自定义信号 / stream_events v3
- 演进步：第 1 版 非流式等到全部完成 → 第 2 版 流式输出进度与逐字 → 第 3 版 业务进度信号与事件流（每步配分步设计图）

### [实战 7：让 agent 记住上一轮聊了什么](07-Memory记忆.md)

- 配套课程：[课 7《Memory 记忆》](../stages/2-Agent核心/lessons/lesson-07-Memory记忆.md)
- 场景：无记忆每轮重开——从「一问一答失忆」到「短期按线程续接 + 裁剪控规模 + 长期跨会话」
- 覆盖知识点：checkpointer 与 thread_id / 裁剪与摘要中间件 / store 长期记忆与合并更新
- 演进步：第 1 版 无记忆每轮重开 → 第 2 版 短期记忆按线程续接 → 第 3 版 短期裁剪与长期跨会话记忆（每步配分步设计图）

## 阶段 3：可控性与可靠性

### [实战 8：给 agent 加日志、限额、重试，别再往业务里塞](08-Middleware中间件.md)

- 配套课程：[课 8《Middleware 中间件》](../stages/3-可控性与可靠性/lessons/lesson-08-Middleware中间件.md)
- 场景：横切逻辑散落——从「业务代码到处塞逻辑」到「内置中间件覆盖 + 自定义补缺 + 顺序确定」
- 覆盖知识点：ModelCallLimit / ToolCallLimit / ToolRetry / ToolError / 自定义 jump 守护 / 组合顺序
- 演进步：第 1 版 横切逻辑散落在业务代码 → 第 2 版 单个中间件抽离 → 第 3 版 多中间件组合与顺序（每步配分步设计图）

### [实战 9：把长对话的上下文瘦下来](09-ContextEngineering上下文工程.md)

- 配套课程：[课 9《Context Engineering 上下文工程》](../stages/3-可控性与可靠性/lessons/lesson-09-ContextEngineering上下文工程.md)
- 场景：全量直塞——从「有什么塞什么」到「动态提示词 + 动态工具 + 瞬时/持久注入 + 工具结果瘦身」
- 覆盖知识点：dynamic_prompt / override(tools) / 瞬时 vs 持久注入 / ClearToolUsesEdit
- 演进步：第 1 版 全量历史直塞 → 第 2 版 动态组装上下文 → 第 3 版 瞬时与持久的分工（每步配分步设计图）
- 与实战 7 的分工：课 7 管「状态里存多少」（裁剪/摘要改状态），本课管「模型这次看到什么」（override 不改状态）

### [实战 10：高风险操作，先让人签个字](10-人机协同与护栏.md)

- 配套课程：[课 10《人机协同与护栏》](../stages/3-可控性与可靠性/lessons/lesson-10-人机协同与护栏.md)
- 场景：高风险操作受控——从「模型直接执行退款」到「中断审批 + PII 脱敏 + 输出审查」
- 覆盖知识点：HumanInTheLoopMiddleware（approve/edit/reject/respond）、when 条件中断、PII 四策略、before/after_agent 自定义护栏
- 演进步：第 1 版 模型直接执行高风险操作 → 第 2 版 中断审批 → 第 3 版 护栏纵深防御（每步配分步设计图）

### [实战 11：让 agent 回答公司内部政策，别让它编](11-Retrieval检索与RAG.md)

- 配套课程：[课 11《Retrieval 检索与 RAG》](../stages/3-可控性与可靠性/lessons/lesson-11-Retrieval检索与RAG.md)
- 场景：私有知识接入——从「直接问模型、没有依据」到「切分 + 向量库 + 检索增强 + 引用溯源」
- 覆盖知识点：RecursiveCharacterTextSplitter、InMemoryVectorStore、similarity_search_with_score、检索工具化、引用溯源
- 演进步：第 1 版 直接问模型没有依据 → 第 2 版 切分与向量检索 → 第 3 版 检索增强与引用溯源（每步配分步设计图）

## 阶段 4：组合与工程化

### [实战 13：给客服 agent 建一道「交付门禁」](13-Testing与Observability.md)

- 配套课程：[课 13《Testing 与 Observability》](../stages/4-组合与工程化/lessons/lesson-13-Testing与Observability.md)
- 场景：客服 agent 交付前的质量门禁——从「人肉验证」到「三层门禁 + 观测」
- 覆盖知识点：为什么 agent 需要测试 / 测试层次 / 可观测性
- 演进步：第 1 版 人肉验证 → 第 2 版 单测工序 → 第 3 版 完整门禁（每步配分步设计图）

### [实战 12：一个 agent 挂 12 个工具之后](12-MultiAgent多智能体.md)

- 配套课程：[课 12《Multi-Agent 多智能体》](../stages/4-组合与工程化/lessons/lesson-12-Multi-Agent多智能体.md)
- 场景：单 agent 工具膨胀后的拆分协作——从「一个 agent 挂满 8 个工具」到「按域拆分 + 四种编排模式」
- 覆盖知识点：subagents（专家包成工具）、handoffs（状态机迁移）、router（分类分派）、skills（按需加载）、自定义工作流
- 演进步：第 1 版 单 agent 挂满工具 → 第 2 版 按域拆分为专家子 agent → 第 3 版 四种编排模式按需选择（每步配分步设计图）


## 计划中

- 结课综合实战项目为**跨阶段整合项目**（覆盖全课程），不属于单课应用实战，产出见课程根目录 `projects/`（收尾阶段生成）。
