# LangGraph Docs 网页索引（docs.langchain.com · Python 版）

> 起始 URL：https://docs.langchain.com/oss/python/langgraph/overview
> 生成日期：2026-10-14 · 范围（scope）：/oss/python/langgraph（另收 9 条强相关的参考 / 迁移 / 集成页）· 条目数：44 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节
> 说明：分区按官方 llms.txt 的一级标题归并（Get started / Capabilities / Production / LangGraph APIs / Frontend），**非站点原结构**。
> ⚠️ 站点已改版：原 `docs.langchain.com/oss/python/langgraph/*` 页面仍可访问，但根 `llms.txt` 已改为 `AGENT DEVELOPMENT LIFECYCLE` 分层结构，LangGraph 页面清单须从 `/_llms/agent-development-lifecycle/build/python.txt` 子索引取；旧版 `langchain-ai.github.io/langgraph/` 为迁移前站点，本索引不覆盖。

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 5 分钟跑通第一个图 | [Quickstart](https://docs.langchain.com/oss/python/langgraph/quickstart.md) | get-started |
| 搞清 LangGraph 与 create_agent 的分工 | [LangGraph overview](https://docs.langchain.com/oss/python/langgraph/overview.md) | get-started |
| 建立"用图思考"的心智模型 | [Thinking in LangGraph](https://docs.langchain.com/oss/python/langgraph/thinking-in-langgraph.md) | get-started |
| 用 StateGraph 定义状态 / 节点 / 边 | [Graph API overview](https://docs.langchain.com/oss/python/langgraph/graph-api.md) | apis |
| 让对话跨会话不断片（checkpointer） | [Checkpointers](https://docs.langchain.com/oss/python/langgraph/checkpointers.md) | capabilities |
| 做跨会话的长期记忆 | [Stores](https://docs.langchain.com/oss/python/langgraph/stores.md) | capabilities |
| 执行中暂停等人工确认 | [Interrupts](https://docs.langchain.com/oss/python/langgraph/interrupts.md) | capabilities |
| 边跑边吐（流式） | [Streaming](https://docs.langchain.com/oss/python/langgraph/streaming.md) | capabilities |
| 回放与分叉重跑 | [Use time-travel](https://docs.langchain.com/oss/python/langgraph/use-time-travel.md) | capabilities |
| 拆子图做多智能体 | [Subgraphs](https://docs.langchain.com/oss/python/langgraph/use-subgraphs.md) | capabilities |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 7 | 上手：overview / install / quickstart / thinking / workflows-agents / local-server / changelog |
| capabilities | [topics/capabilities.md](./topics/capabilities.md) | 10 | 能力：persistence / checkpointers / stores / memory / streaming / event-streaming / interrupts / time-travel / fault-tolerance / subgraphs |
| production | [topics/production.md](./topics/production.md) | 7 | 生产：application-structure / test / backward-compatibility / studio / ui / deploy / observability |
| apis | [topics/apis.md](./topics/apis.md) | 6 | 两套 API：choosing-apis / graph-api / use-graph-api / functional-api / use-functional-api / pregel |
| frontend | [topics/frontend.md](./topics/frontend.md) | 5 | 前端集成 + 官方教程（RAG agent / SQL agent） |
| reference | [topics/reference.md](./topics/reference.md) | 9 | Python SDK 参考、v1 发布与迁移、checkpointer / store 集成、产品选型 |
