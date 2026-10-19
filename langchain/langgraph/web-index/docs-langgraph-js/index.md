# LangGraph Docs 网页索引（docs.langchain.com · JS/TS 版）

> 起始 URL：https://docs.langchain.com/oss/javascript/langgraph/overview
> 生成日期：2026-10-19 · 范围（scope）：/oss/javascript/langgraph · 条目数：35 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL 取细节
> **本索引全部 35 条链接于 2026-10-19 用 HTTP 请求逐条实测，均返回 200**（非照抄其他教程的旧表）
> 说明：分区为按本教程 4 阶段教学内容**人工归并**（与 Python 版 `docs-langgraph` 的分区一一对应，便于左右对照），非站点原结构。

## 与 Python 版索引的关系

| 索引 | slug | 范围 | 用途 |
|---|---|---|---|
| LangGraph Docs（Python） | docs-langgraph | /oss/python/langgraph | 课文 Python 代码块的依据（44 条） |
| **LangGraph Docs（JS/TS）** | **docs-langgraph-js** | **/oss/javascript/langgraph** | **课文 TypeScript 代码块的依据（本文件，35 条）** |

写课规则：同一知识点若两侧都有页面，Python 代码查 `docs-langgraph`，TS 代码查本索引；两侧写法冲突时以各自官方页面为准，并在课文中标注差异。

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 5 分钟跑通第一个图（TS） | [Quickstart](https://docs.langchain.com/oss/javascript/langgraph/quickstart.md) | get-started |
| 搞清 LangGraph 在生态中的位置 | [Overview](https://docs.langchain.com/oss/javascript/langgraph/overview.md) | get-started |
| 建立"用图思考"的心智模型 | [Thinking in LangGraph](https://docs.langchain.com/oss/javascript/langgraph/thinking-in-langgraph.md) | get-started |
| 用 StateGraph 定义状态 / 节点 / 边 | [Graph API](https://docs.langchain.com/oss/javascript/langgraph/graph-api.md) | apis |
| 用 entrypoint / task 写函数式流程 | [Functional API](https://docs.langchain.com/oss/javascript/langgraph/functional-api.md) | apis |
| 让对话跨会话不断片（checkpointer） | [Checkpointers](https://docs.langchain.com/oss/javascript/langgraph/checkpointers.md) | capabilities |
| 做跨会话的长期记忆（store） | [Stores](https://docs.langchain.com/oss/javascript/langgraph/stores.md) | capabilities |
| 执行中暂停等人工确认 | [Interrupts](https://docs.langchain.com/oss/javascript/langgraph/interrupts.md) | capabilities |
| 边跑边吐（流式） | [Streaming](https://docs.langchain.com/oss/javascript/langgraph/streaming.md) | capabilities |
| 回放与分叉重跑 | [Time travel](https://docs.langchain.com/oss/javascript/langgraph/use-time-travel.md) | patterns |
| 拆子图 / 嵌套 | [Subgraphs](https://docs.langchain.com/oss/javascript/langgraph/use-subgraphs.md) | patterns |
| 节点级重试 / 超时 | [Fault tolerance](https://docs.langchain.com/oss/javascript/langgraph/fault-tolerance.md) | capabilities |
| 测试图与状态（TS） | [Testing](https://docs.langchain.com/oss/javascript/langgraph/test.md) | production |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 7 | 上手：根索引 / overview / install / quickstart / thinking / workflows-agents / local-server |
| capabilities | [topics/capabilities.md](./topics/capabilities.md) | 11 | 能力：persistence / checkpointers / stores / add-memory / streaming / event-streaming / interrupts / time-travel / fault-tolerance / subgraphs / agentic-rag |
| apis | [topics/apis.md](./topics/apis.md) | 6 | 两套 API：choosing-apis / graph-api / use-graph-api / functional-api / use-functional-api / pregel |
| production | [topics/production.md](./topics/production.md) | 11 | 工程化与上线：application-structure / test / backward-compatibility / studio / ui / deploy / observability / case-studies / frontend（overview、graph-execution、custom-stream-channels） |

> 合计 35 条（7 + 11 + 6 + 11）。Python 版的 9 条强相关参考页含 py 专用 SDK 与迁移页，TS 侧无逐条对应，需要时查官方站点或 `docs-langchain-js`。

## 已验证链接清单（2026-10-19 实测 200，共 35 条）

```
根索引        oss/javascript/langgraph
get-started   overview  install  quickstart  thinking-in-langgraph  workflows-agents  local-server
capabilities  persistence  checkpointers  stores  add-memory  streaming  event-streaming
              interrupts  use-time-travel  fault-tolerance  use-subgraphs  agentic-rag
apis          choosing-apis  graph-api  use-graph-api  functional-api  use-functional-api  pregel
production    application-structure  test  backward-compatibility  studio  ui  deploy
              observability  case-studies  frontend/overview  frontend/graph-execution
              frontend/custom-stream-channels
```

## 相关索引

| 索引 | slug | 范围 | 说明 |
|------|------|------|------|
| LangChain Docs（JS/TS 版） | docs-langchain-js | /oss/javascript/langchain | 同生态组件层 TS 索引（在 `../langchain/web-index/`，67 条） |
| LangChain Docs（Python 版） | docs-langchain | /oss/python/langchain | 同生态组件层 Python 索引 |
| LangGraph Docs（Python 版） | docs-langgraph | /oss/python/langgraph | 本教程 Python 代码依据（44 条） |
