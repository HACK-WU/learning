# Deep Agents Docs 网页索引（docs.langchain.com · TypeScript 版）

> 起始 URL：https://docs.langchain.com/oss/javascript/deepagents/overview
> 生成日期：2026-10-21 · 范围（scope）：/oss/javascript/deepagents · 条目数：30 · 一次性快照
> 版本基线：`deepagents 1.15.1`（npm）
> 只索引不镜像：需要正文时打开对应 URL 取细节
> 说明：分区为按教学内容**人工归并**（站点 llms.txt 无细分分区），非站点原结构

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 打开该条 URL 取细节
3. 与 Python 版索引（`../docs-deepagents/`）配合使用：同一能力优先读 Python 版（课程主线），需要 TS 写法和参数名时读本索引
4. 本表是快照，链接大面积失效时整站重跑重建

## 与 Python 版的对照结论

两版页面集合并非一一对应。本索引多出 Python 版没有的 7 页：`comparison`、`models`、`multimodal`、`rag`、`retrieval`、`streaming`、`content-builder`、`frontend`、`profiles`、`going-to-production`（部分页面 Python 版以不同 slug 收录）。差异详见 `playground-ts/API-MAPPING.md`。

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 跑通第一个 deep agent | [Quickstart](https://docs.langchain.com/oss/javascript/deepagents/quickstart.md) | get-started |
| 搞清它和 createAgent / LangGraph 的分工 | [Overview](https://docs.langchain.com/oss/javascript/deepagents/overview.md) | get-started |
| 改 system prompt / 换模型 / 装工具 / 配子代理 | [Customize](https://docs.langchain.com/oss/javascript/deepagents/customization.md) | get-started |
| 选文件存哪（内存 / 磁盘 / Store / 路由） | [Backends](https://docs.langchain.com/oss/javascript/deepagents/backends.md) | execution |
| 限制 agent 能读能写哪些路径 | [Permissions](https://docs.langchain.com/oss/javascript/deepagents/permissions.md) | execution |
| 让它执行 shell / 跑测试 / 装依赖 | [Sandboxes](https://docs.langchain.com/oss/javascript/deepagents/sandboxes.md) | execution |
| 给它一个轻量可编程层（不碰 shell） | [Interpreters](https://docs.langchain.com/oss/javascript/deepagents/interpreters.md) | execution |
| 接 MCP 服务 | [Tools](https://docs.langchain.com/oss/javascript/deepagents/tools.md) | execution |
| 把团队 SOP 做成按需加载的技能 | [Skills](https://docs.langchain.com/oss/javascript/deepagents/skills.md) | context |
| 跨会话记住项目规范 | [Memory](https://docs.langchain.com/oss/javascript/deepagents/memory.md) | context |
| 长任务不爆上下文 | [Context engineering](https://docs.langchain.com/oss/javascript/deepagents/context-engineering.md) | context |
| 让主代理派活给子代理 | [Subagents](https://docs.langchain.com/oss/javascript/deepagents/subagents.md) | delegation |
| 后台并行跑子代理、还能中途改主意 | [Async subagents](https://docs.langchain.com/oss/javascript/deepagents/async-subagents.md) | delegation |
| 按运行时条件动态决定派谁 | [Dynamic subagents](https://docs.langchain.com/oss/javascript/deepagents/dynamic-subagents.md) | delegation |
| 高危工具执行前要人点同意 | [Human-in-the-loop](https://docs.langchain.com/oss/javascript/deepagents/human-in-the-loop.md) | delegation |
| 流式吐出子代理的过程 | [Event streaming](https://docs.langchain.com/oss/javascript/deepagents/event-streaming.md) | production |
| 上线前加重试 / 次数上限 / 降级 | [Fault tolerance](https://docs.langchain.com/oss/javascript/deepagents/fault-tolerance.md) | production |
| 上线前的完整检查项 | [Going to production](https://docs.langchain.com/oss/javascript/deepagents/going-to-production.md) | production |
| 接 IDE / 接前端协议 | [ACP](https://docs.langchain.com/oss/javascript/deepagents/acp.md) / [AG-UI](https://docs.langchain.com/oss/javascript/deepagents/ag-ui.md) | production |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | `topics/get-started.md` | 4 | overview / quickstart / customization / comparison |
| execution | `topics/execution-environment.md` | 6 | backends / permissions / sandboxes / interpreters / tools / models |
| context | `topics/context-management.md` | 5 | skills / memory / context-engineering / multimodal / rag |
| delegation | `topics/delegation-steering.md` | 5 | subagents / async-subagents / dynamic-subagents / human-in-the-loop / retrieval |
| production | `topics/production-frontend.md` | 8 | event-streaming / fault-tolerance / going-to-production / acp / ag-ui / frontend / profiles / content-builder |
| 合计 | | 30 | 含 overview 与 streaming 两个跨区页面 |

## 维护说明

- 重建命令思路：抓 `https://docs.langchain.com/sitemap.xml`，`grep -o "https://docs.langchain.com/oss/javascript/deepagents/[a-z0-9-]*"` 去重即得全部页
- 页面正文取法：URL 末尾加 `.md` 直接返回 Markdown（官网支持，比抓 HTML 干净）
- 本索引不镜像正文，仅存路由
