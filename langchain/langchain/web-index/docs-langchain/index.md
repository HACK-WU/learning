# LangChain Docs 网页索引（docs.langchain.com · Python 版）

> 起始 URL：https://docs.langchain.com/oss/python/langchain/overview
> 生成日期：2026-09-15 · 范围（scope）：/oss/python/langchain · 条目数：76 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节
> 说明：分区为按教学内容**人工归并**（站点 llms.txt 无细分分区），非站点原结构

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 跑通第一个 agent（快速上手） | [Quickstart](https://docs.langchain.com/oss/python/langchain/quickstart.md) | meta |
| 查 create_agent 的用法与参数 | [Agents](https://docs.langchain.com/oss/python/langchain/agents.md) | core |
| 接入模型 / 换 provider / 自定义 endpoint | [Models](https://docs.langchain.com/oss/python/langchain/models.md) | core |
| 写一个工具（@tool、参数 schema） | [Tools](https://docs.langchain.com/oss/python/langchain/tools.md) | core |
| 在 agent loop 里加逻辑（拦截/重试/摘要） | [Middleware Overview](https://docs.langchain.com/oss/python/langchain/middleware/overview.md) | core |
| 做流式输出（token 逐字） | [Streaming](https://docs.langchain.com/oss/python/langchain/streaming.md) | core |
| 让对话有记忆（短期/长期） | [Short-term memory](https://docs.langchain.com/oss/python/langchain/short-term-memory.md) | core |
| 输出固定结构的 JSON | [Structured output](https://docs.langchain.com/oss/python/langchain/structured-output.md) | core |
| 高危操作加人工审批（HITL） | [Human-in-the-loop](https://docs.langchain.com/oss/python/langchain/human-in-the-loop.md) | core |
| 接入 tracing 调试 agent | [LangSmith Observability](https://docs.langchain.com/oss/python/langchain/observability.md) | agent-quality |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| core | [topics/core-components.md](./topics/core-components.md) | 20 | 核心组件：agents / models / messages / tools / middleware / memory / streaming / structured output / context / HITL / guardrails / mcp / retrieval / runtime |
| multi-agent | [topics/multi-agent.md](./topics/multi-agent.md) | 10 | 多智能体：subagents / handoffs / router / skills / custom workflow + 示例教程 |
| agent-quality | [topics/agent-quality.md](./topics/agent-quality.md) | 6 | 测试（unit / integration / evals）与可观测（observability / studio） |
| frontend | [topics/frontend.md](./topics/frontend.md) | 20 | 前端集成：generative UI / 流式 UI / 消息渲染 / 集成框架（延伸方向） |
| errors | [topics/errors.md](./topics/errors.md) | 7 | 官方错误码：认证 / 模型 / 消息 / 工具 / 解析类报错 |
| tutorials | [topics/tutorials.md](./topics/tutorials.md) | 4 | 实战教程：SQL agent / 数据分析 agent / 知识库 / 语音 agent |
| meta | [topics/meta.md](./topics/meta.md) | 9 | 元信息：安装 / 理念与历史 / Academy / 更新日志 / 部署 / 帮助 |
