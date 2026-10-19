# LangChain Docs 网页索引（docs.langchain.com · JS/TypeScript 版）

> 起始 URL：https://docs.langchain.com/oss/javascript/langchain/overview
> 生成日期：2026-10-16 · 范围（scope）：/oss/javascript/langchain · 条目数：67 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节
> 说明：分区为按教学内容**人工归并**（站点 llms.txt 无细分分区），非站点原结构；对应 Python 版索引「docs-langchain」

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 跑通第一个 agent（快速上手，TS） | [Quickstart](https://docs.langchain.com/oss/javascript/langchain/quickstart.md) | meta |
| 查 create_agent 的用法与参数（TS） | [Agents](https://docs.langchain.com/oss/javascript/langchain/agents.md) | core |
| 接入模型 / 换 provider / 自定义 endpoint（TS） | [Models](https://docs.langchain.com/oss/javascript/langchain/models.md) | core |
| 写一个工具（tool、zod 参数 schema） | [Tools](https://docs.langchain.com/oss/javascript/langchain/tools.md) | core |
| 在 agent loop 里加逻辑（拦截/重试/摘要） | [Middleware Overview](https://docs.langchain.com/oss/javascript/langchain/middleware/overview.md) | core |
| 做流式输出（token 逐字，TS） | [Streaming](https://docs.langchain.com/oss/javascript/langchain/streaming.md) | core |
| 让对话有记忆（短期/长期） | [Long-term memory](https://docs.langchain.com/oss/javascript/langchain/long-term-memory.md) | core |
| 输出固定结构的 JSON（TS） | [Structured output](https://docs.langchain.com/oss/javascript/langchain/structured-output.md) | core |
| 高危操作加人工审批（HITL） | [Human-in-the-loop](https://docs.langchain.com/oss/javascript/langchain/human-in-the-loop.md) | core |
| 接入 tracing 调试 agent（TS） | [LangSmith Observability](https://docs.langchain.com/oss/javascript/langchain/observability.md) | agent-quality |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| core | [topics/core-components.md](./topics/core-components.md) | 22 | 核心组件（TS）：agents / models / messages / tools / middleware / memory / streaming / structured output / context / HITL / guardrails / runtime / MCP |
| multi-agent | [topics/multi-agent.md](./topics/multi-agent.md) | 6+4 | 多智能体：subagents / handoffs / skills / router / custom workflow（另并入 4 条教程相关页） |
| agent-quality | [topics/agent-quality.md](./topics/agent-quality.md) | 6 | 测试（unit / integration / evals）、知识库与可观测（observability / studio） |
| frontend | [topics/frontend.md](./topics/frontend.md) | 20 | 前端集成（TS）：generative UI / 流式 UI / 消息渲染 / 集成框架 / time travel |
| meta | [topics/meta.md](./topics/meta.md) | 7 | 元信息：安装 / 概览 / 理念 / 快速上手 / 部署 / 组件架构 / 帮助 |
| tutorials | [topics/tutorials.md](./topics/tutorials.md) | 2 | 端到端示例：SQL agent / voice agent |

## 相关索引

| 索引 | slug | 范围 | 说明 |
|------|------|------|------|
| LangChain Docs（Python 版） | docs-langchain | /oss/python/langchain | 教程既有 Python 索引 |
| LangGraph Docs（JS/TS 版） | docs-langgraph-js | /oss/javascript/langgraph | 记忆 / Multi-Agent 的 TS 参考（34 条） |