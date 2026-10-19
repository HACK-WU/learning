# LangGraph Docs 网页索引（docs.langchain.com · JS/TS 版）

> 起始 URL：https://docs.langchain.com/oss/javascript/langgraph/overview
> 生成日期：2026-10-16 · 范围（scope）：/oss/javascript/langgraph · 条目数：34 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节
> 说明：分区为按教学内容**人工归并**（站点 llms.txt 无细分分区），非站点原结构；配套索引见「docs-langchain-js」

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| Graph API 怎么用（节点 / 边 / 状态） | [Graph API](https://docs.langchain.com/oss/javascript/langgraph/graph-api.md) | core |
| 加持久化 / checkpointer（TS） | [Persistence](https://docs.langchain.com/oss/javascript/langgraph/persistence.md) | core |
| checkpointer 家族与选择（存对话状态） | [Checkpointers](https://docs.langchain.com/oss/javascript/langgraph/checkpointers.md) | core |
| 跨线程长期记忆（store） | [Stores](https://docs.langchain.com/oss/javascript/langgraph/stores.md) | core |
| 图执行流式输出（stream modes） | [Streaming](https://docs.langchain.com/oss/javascript/langgraph/streaming.md) | core |
| 做中断 / 恢复（interrupt / resume） | [Interrupts](https://docs.langchain.com/oss/javascript/langgraph/interrupts.md) | core |
| 用子图拆分复杂图 | [Subgraphs](https://docs.langchain.com/oss/javascript/langgraph/use-subgraphs.md) | patterns |
| 从历史 checkpoint 回放（时光旅行） | [Time travel](https://docs.langchain.com/oss/javascript/langgraph/use-time-travel.md) | patterns |
| 测试图与状态（TS） | [Testing](https://docs.langchain.com/oss/javascript/langgraph/test.md) | quality |
| 图执行的前端可视化 | [Frontend overview](https://docs.langchain.com/oss/javascript/langgraph/frontend/overview.md) | frontend |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| core | [topics/core.md](./topics/core.md) | 12 | Graph / Functional API、persistence、checkpointers、stores、memory、streaming、interrupts、容错 |
| patterns | [topics/patterns.md](./topics/patterns.md) | 5 | subgraphs / time travel / workflows-agents / agentic-rag / pregel |
| quality | [topics/quality.md](./topics/quality.md) | 4 | testing / observability / studio / case studies |
| frontend | [topics/frontend.md](./topics/frontend.md) | 4 | 前端集成：图执行 UI / 自定义流通道 / ui |
| meta | [topics/meta.md](./topics/meta.md) | 9 | 元信息：安装 / 概览 / 快速上手 / 选择 API / 应用结构 / 部署 / 本地 server |

## 相关索引

| 索引 | slug | 范围 | 说明 |
|------|------|------|------|
| LangChain Docs（JS/TS 版） | docs-langchain-js | /oss/javascript/langchain | 教程核心 TS 索引（67 条） |
| LangChain Docs（Python 版） | docs-langchain | /oss/python/langchain | 教程既有 Python 索引 |