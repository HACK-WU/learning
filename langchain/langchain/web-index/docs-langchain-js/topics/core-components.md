# 核心组件（LangChain JS/TS · 共 22 条）

> 范围：/oss/javascript/langchain · 生成日期：2026-10-16

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 看懂 LangChain 组件架构与各层职责 | [Component architecture](https://docs.langchain.com/oss/javascript/langchain/component-architecture.md) | | 组件、架构、分层 | [Overview](https://docs.langchain.com/oss/javascript/langchain/overview.md) |
| 建一个 agent：模型循环调用工具（TS） | [Agents](https://docs.langchain.com/oss/javascript/langchain/agents.md) | | create_agent、agent、Harness | [Quickstart](https://docs.langchain.com/oss/javascript/langchain/quickstart.md) |
| 初始化/配置聊天模型，换 provider | [Models](https://docs.langchain.com/oss/javascript/langchain/models.md) | | ChatOpenAI、模型、provider、endpoint | |
| 构造与操作消息对象（Human/AI/Tool） | [Messages](https://docs.langchain.com/oss/javascript/langchain/messages.md) | | message、SystemMessage、消息类型 | |
| 定义工具：给 agent 接函数/API/数据库 | [Tools](https://docs.langchain.com/oss/javascript/langchain/tools.md) | | tool、zod、schema、工具定义 | [Tool calling UI](https://docs.langchain.com/oss/javascript/langchain/frontend/tool-calling.md) |
| 让对话有短期记忆（会话内状态） | [Short-term memory](https://docs.langchain.com/oss/javascript/langchain/short-term-memory.md) | | 短期记忆、MemorySaver | [Long-term memory](https://docs.langchain.com/oss/javascript/langchain/long-term-memory.md) |
| 跨会话长期记忆存储与召回 | [Long-term memory](https://docs.langchain.com/oss/javascript/langchain/long-term-memory.md) | | 长期记忆、Store、召回 | |
| 做 token 级流式输出（TS） | [Streaming](https://docs.langchain.com/oss/javascript/langchain/streaming.md) | | streaming、流式、AsyncIterator | [Event streaming](https://docs.langchain.com/oss/javascript/langchain/event-streaming.md) |
| 流式事件（agent 状态/工具调用事件） | [Event streaming](https://docs.langchain.com/oss/javascript/langchain/event-streaming.md) | | 事件流、chunk、类型 | |
| 输出固定结构 JSON / 结构化输出 | [Structured output](https://docs.langchain.com/oss/javascript/langchain/structured-output.md) | | structured、schema、zod | |
| 控制 agent 上下文注入与压缩 | [Context engineering](https://docs.langchain.com/oss/javascript/langchain/context-engineering.md) | | context、提示词、上下文管理 | |
| 高危操作加人工审批（HITL） | [Human-in-the-loop](https://docs.langchain.com/oss/javascript/langchain/human-in-the-loop.md) | | HITL、interrupt、审批 | |
| 运行时配置（模型路由/终态） | [Runtime](https://docs.langchain.com/oss/javascript/langchain/runtime.md) | | runtime、路由、初始化 | |
| 给 agent 加安全护栏 / 内容过滤 | [Guardrails](https://docs.langchain.com/oss/javascript/langchain/guardrails.md) | | guardrails、安全、过滤 | |
| 在 agent loop 里加逻辑（拦截/重试/摘要） | [Middleware overview](https://docs.langchain.com/oss/javascript/langchain/middleware/overview.md) | | middleware、createMiddleware、中间件 | |
| 用预置中间件实现常见场景 | [Prebuilt middleware](https://docs.langchain.com/oss/javascript/langchain/middleware/built-in.md) | | 预置中间件、内置 | |
| 写自定义 middleware（TS） | [Custom middleware](https://docs.langchain.com/oss/javascript/langchain/middleware/custom.md) | | 自定义中间件、实现 | |
| 连接 MCP server（MCPAdapter 对接） | [MCP overview](https://docs.langchain.com/oss/javascript/langchain/mcp/index.md) | | MCP、MCPAdapter、服务器 | |
| 把 MCP 工具接入 agent 并控制执行 | [MCP tools](https://docs.langchain.com/oss/javascript/langchain/mcp/tools.md) | | MCP 工具、加载、执行 | |
| MCP 连接生命周期 / 多服务器 / 缓存 | [MCP connections](https://docs.langchain.com/oss/javascript/langchain/mcp/connections.md) | | 连接、生命周期、缓存 | |
| MCP 认证（OAuth2.1 / bearer / 用户凭证） | [MCP auth](https://docs.langchain.com/oss/javascript/langchain/mcp/auth.md) | | MCP、认证、OAuth | |
| 建知识库 agent（检索增强） | [Knowledge base](https://docs.langchain.com/oss/javascript/langchain/knowledge-base.md) | | 知识库、RAG、检索 | |