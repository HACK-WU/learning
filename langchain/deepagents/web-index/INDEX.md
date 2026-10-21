# Deep Agents 教程 · 网页索引登记表

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再取正文。
> 本索引落在本教程目录内（仓库路径 `langchain/deepagents/web-index/`），供各课「📚 官方文档」链接与事实核查使用（Step 1.4）。

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| Deep Agents Docs（Python 版） | docs-deepagents | https://docs.langchain.com/oss/python/deepagents/overview | /oss/python/deepagents | 34 | 2026-10-20 |

## 同生态其它索引

| 站点 | slug | 位置 | 用途 |
|------|------|------|------|
| LangChain Docs（Python 版） | docs-langchain | `../../langchain/web-index/docs-langchain/index.md` | Deep Agents 建在 LangChain 之上（`create_agent` / middleware / messages），涉及底层概念时查它 |
| LangChain Docs（JS/TS 版） | docs-langchain-js | `../../langchain/web-index/docs-langchain-js/index.md` | 双语代码块的 TS 侧写法基准 |
| LangGraph Docs（JS/TS 版） | docs-langgraph-js | `../../langchain/web-index/docs-langgraph-js/index.md` | Deep Agents 用 LangGraph 运行时（durable execution / interrupt） |

## 说明

- **只索引不镜像**：需要正文时打开 URL 取细节；索引只解决"去哪一页"，不解决"内容是否过时"
- **`middleware` 页已迁移**：`/oss/python/deepagents/middleware` 现 307 跳转到 LangChain 的 middleware 分区（官方把中间件文档收归 LangChain 侧），故本索引不单列该页
- **版本基线**：`deepagents 0.7.28`（PyPI，要求 Python >=3.11,<4.0，核对于 2026-10）
- **三条 v0.7 破坏性变更**已写入索引备注（任务规划转 opt-in / `delete` 工具新增且需 >=0.7 / 无删除能力的后端自动隐藏该工具），写课时直接对照，不现场翻
