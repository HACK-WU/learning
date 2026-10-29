# Managed Deep Agents 教程 · 网页索引登记表

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再取正文。
> 本索引落在本教程目录内（仓库路径 `langchain/managed-deep-agents/web-index/`），供各课「📚 官方文档」链接与事实核查使用。

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| Managed Deep Agents Docs（Python 版） | docs-managed-deep-agents | https://docs.langchain.com/langsmith/python/managed-deep-agents-overview | `/langsmith/python/managed-deep-agents*` | 29 | 2026-10-28 |
| Managed Deep Agents Docs（TypeScript 版） | docs-managed-deep-agents-js | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-overview | `/langsmith/javascript/managed-deep-agents*` | 29 | 2026-10-28 |

详细路由表：

- [Python 版索引](./docs-managed-deep-agents/index.md)
- [TypeScript 版索引](./docs-managed-deep-agents-js/index.md)

## 两侧关系

**页面集合完全一致（29 / 29，标题逐条相同）。** 2026-10-28 用官方 `llms.txt` 两侧清单逐条 diff 实测。差异不在页面结构，而在页面内的 API 名与示例代码——那部分统一沉淀在 [`playground-ts/API-MAPPING.md`](../playground-ts/API-MAPPING.md)，本目录不重复维护。

## 同生态其它索引

| 站点 | slug | 位置 | 用途 |
|------|------|------|------|
| Deep Agents Docs（Python 版） | docs-deepagents | [`../../deepagents/web-index/docs-deepagents/index.md`](../../deepagents/web-index/docs-deepagents/index.md) | MDA 跑的就是这套 harness，讲到 `create_deep_agent` / 中间件 / 子代理时查它 |
| Deep Agents Docs（TS 版） | docs-deepagents-js | [`../../deepagents/web-index/docs-deepagents-js/index.md`](../../deepagents/web-index/docs-deepagents-js/index.md) | TS 侧 harness 的写法基准 |
| LangChain Docs（Python 版） | docs-langchain | [`../../langchain/web-index/docs-langchain/index.md`](../../langchain/web-index/docs-langchain/index.md) | 底层概念（`create_agent` / middleware / messages） |
| LangChain Docs（JS/TS 版） | docs-langchain-js | [`../../langchain/web-index/docs-langchain-js/index.md`](../../langchain/web-index/docs-langchain-js/index.md) | 双语代码块的 TS 侧写法基准 |
| LangGraph Docs（TS 版） | docs-langgraph-js | [`../../langgraph/web-index/docs-langgraph-js/index.md`](../../langgraph/web-index/docs-langgraph-js/index.md) | 运行时语义（durable execution / interrupt） |

## 说明

- **只索引不镜像**：需要正文时打开 URL 取细节；索引只解决"去哪一页"，不解决"内容是否过时"
- **数据来源可信**：29 条来自官方 `llms.txt` 索引树（`_llms/agent-development-lifecycle/build/python.txt` / `.../type-script.txt`），不是从 sitemap 猜的；58 条 URL 全部实测 HTTP 200
- **一句话措辞不外编**：分区表「一句话」列取自该页官方副标题（Markdown 的 `>` 引言行），不是自己概括
- **版本基线**：`managed-deepagents 0.9.5`（PyPI）/ `managed-deepagents@0.9.5`（npm），核对于 2026-10
- **重建方式**：见两个子索引末尾的「维护说明」
