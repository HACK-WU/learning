# Deep Agents Docs 网页索引（docs.langchain.com · Python 版）

> 起始 URL：https://docs.langchain.com/oss/python/deepagents/overview
> 生成日期：2026-10-20 · 范围（scope）：/oss/python/deepagents · 条目数：34 · 一次性快照
> 版本基线：`deepagents 0.7.28`
> 只索引不镜像：需要正文时打开对应 URL 取细节
> 说明：分区为按教学内容**人工归并**（站点 llms.txt 无细分分区），非站点原结构

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 跑通第一个 deep agent | [Quickstart](https://docs.langchain.com/oss/python/deepagents/quickstart.md) | get-started |
| 搞清它和 create_agent / LangGraph 的分工 | [Overview](https://docs.langchain.com/oss/python/deepagents/overview.md) | get-started |
| 改 system prompt / 换模型 / 装工具 / 配子代理 | [Customize](https://docs.langchain.com/oss/python/deepagents/customization.md) | get-started |
| 选文件存哪（内存 / 磁盘 / Store / 路由） | [Backends](https://docs.langchain.com/oss/python/deepagents/backends.md) | execution |
| 限制 agent 能读能写哪些路径 | [Permissions](https://docs.langchain.com/oss/python/deepagents/permissions.md) | execution |
| 让它执行 shell / 跑测试 / 装依赖 | [Sandboxes](https://docs.langchain.com/oss/python/deepagents/sandboxes.md) | execution |
| 给它一个轻量可编程层（不碰 shell） | [Interpreters](https://docs.langchain.com/oss/python/deepagents/interpreters.md) | execution |
| 接 MCP 服务 | [Tools](https://docs.langchain.com/oss/python/deepagents/tools.md) | execution |
| 把团队 SOP 做成按需加载的技能 | [Skills](https://docs.langchain.com/oss/python/deepagents/skills.md) | context |
| 跨会话记住项目规范 | [Memory](https://docs.langchain.com/oss/python/deepagents/memory.md) | context |
| 长任务不爆上下文 | [Context engineering](https://docs.langchain.com/oss/python/deepagents/context-engineering.md) | context |
| 让主代理派活给子代理 | [Subagents](https://docs.langchain.com/oss/python/deepagents/subagents.md) | delegation |
| 后台并行跑子代理、还能中途改主意 | [Async subagents](https://docs.langchain.com/oss/python/deepagents/async-subagents.md) | delegation |
| 高危工具执行前要人点同意 | [Human-in-the-loop](https://docs.langchain.com/oss/python/deepagents/human-in-the-loop.md) | delegation |
| 流式吐出子代理的过程 | [Event streaming](https://docs.langchain.com/oss/python/deepagents/event-streaming.md) | production |
| 上线前加重试 / 次数上限 / 降级 | [Fault tolerance](https://docs.langchain.com/oss/python/deepagents/fault-tolerance.md) | production |
| 接 IDE / 接前端协议 | [ACP](https://docs.langchain.com/oss/python/deepagents/acp.md) / [AG-UI](https://docs.langchain.com/oss/python/deepagents/ag-ui.md) | production |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 6 | 总览 / 快速开始 / 定制 / 模型 / 与 Claude Agent SDK 对比 / Profiles |
| execution | [topics/execution-environment.md](./topics/execution-environment.md) | 6 | 工具与 MCP / 后端 / 权限 / 多模态 / 沙箱 / 解释器 |
| context | [topics/context-management.md](./topics/context-management.md) | 4 | 技能 / 记忆 / 检索 / 上下文工程 |
| delegation | [topics/delegation-steering.md](./topics/delegation-steering.md) | 4 | 子代理 / 动态子代理 / 异步子代理 / 人在环中 |
| production | [topics/production-frontend.md](./topics/production-frontend.md) | 14 | 生产化 / 容错 / 流式与事件流 / 前端四页 / 协议两页 / 三篇教程 |

## 版本要点（写课时先看这里，别现场翻）

| 变更 | 内容 | 影响课程 |
|------|------|----------|
| v0.7 任务规划转 opt-in | 早期版本默认带 planning middleware，v0.7 起需显式传入 `TodoListMiddleware` 才有 `write_todos` 工具 | 课 10 |
| v0.7 新增 `delete` 工具 | 需 `deepagents>=0.7`；**不支持删除的后端会把该工具自动从模型可见工具中隐藏** | 课 4 |
| 权限不覆盖沙箱 | 声明式权限只作用于内置文件工具，**沙箱后端可任意执行命令，权限规则管不到** | 课 5 |
| 提示缓存自动生效范围 | 仅 Anthropic 与 Amazon Bedrock（Claude/Nova）默认开启，其它 provider 需另配中间件 | 课 9 |
| `middleware` 页迁址 | `/oss/python/deepagents/middleware` 307 → LangChain middleware 分区 | 全课（引链接时别写 deepagents 路径） |
