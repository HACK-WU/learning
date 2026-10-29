# Managed Deep Agents Docs 网页索引（docs.langchain.com · Python 版）

> 起始 URL：https://docs.langchain.com/langsmith/python/managed-deep-agents-overview
> 生成日期：2026-10-28 · 范围（scope）：`/langsmith/python/managed-deep-agents*` · 条目数：29 · 一次性快照
> 版本基线：`managed-deepagents 0.9.5`（PyPI）· 核对于 2026-10
> 数据来源：官方 `llms.txt` 索引树（`_llms/agent-development-lifecycle/build/python.txt`）逐条提取，29 条 URL 全部实测 HTTP 200
> 只索引不镜像：需要正文时打开对应 URL 取细节
> 说明：分区为按教学内容**人工归并**，非站点原结构（`llms.txt` 只给平铺清单）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 打开该条 URL 取细节；URL 末尾加 `.md` 直接返回 Markdown，比抓 HTML 干净
3. 双语课程优先读本索引（Python 是主线），要 TS 写法与参数名时转 [TS 版索引](../docs-managed-deep-agents-js/index.md)
4. 本表是快照。链接大面积失效时整站重跑重建，重建方法见文末「维护说明」

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 搞清 MDA 到底替我接管了什么 | [Overview](https://docs.langchain.com/langsmith/python/managed-deep-agents-overview.md) | get-started |
| 从零跑通第一个可部署项目 | [Quickstart](https://docs.langchain.com/langsmith/python/managed-deep-agents-quickstart.md) | get-started |
| 知道哪些目录名是"被发现的"、哪些只是普通模块 | [Project structure](https://docs.langchain.com/langsmith/python/managed-deep-agents-project-structure.md) | get-started |
| 把已有 `create_deep_agent` 的 agent 搬过来 | [Migrate](https://docs.langchain.com/langsmith/python/managed-deep-agents-migrate.md) | get-started |
| 配模型、写 `agent.py` 入口 | [Agent definition](https://docs.langchain.com/langsmith/python/managed-deep-agents-agent-definition.md) | capability |
| 写常驻系统提示 | [Instructions](https://docs.langchain.com/langsmith/python/managed-deep-agents-instructions.md) | capability |
| 把 SOP 做成按需加载的技能 | [Skills](https://docs.langchain.com/langsmith/python/managed-deep-agents-skills.md) | capability |
| 加一个要读内部 API 的自定义工具 | [Tools](https://docs.langchain.com/langsmith/python/managed-deep-agents-tools.md) | capability |
| 用平台内置搜索、不另配 key | [Search](https://docs.langchain.com/langsmith/python/managed-deep-agents-search.md) | capability |
| 存 API key 与 OAuth 授权 | [Connections](https://docs.langchain.com/langsmith/python/managed-deep-agents-connections.md) | capability |
| 接远程 MCP 服务的工具 | [MCP connectors](https://docs.langchain.com/langsmith/python/managed-deep-agents-mcp-connectors.md) | capability |
| 在模型调用 / 工具调用前后插逻辑 | [Middleware](https://docs.langchain.com/langsmith/python/managed-deep-agents-middleware.md) | capability |
| 让 agent 跨会话记住东西 | [Memory](https://docs.langchain.com/langsmith/python/managed-deep-agents-memory.md) | memory-sandbox |
| 给它一个能跑命令的隔离环境 | [Sandboxes](https://docs.langchain.com/langsmith/python/managed-deep-agents-sandboxes.md) | memory-sandbox |
| 控制"谁能调用这个部署" | [Identity](https://docs.langchain.com/langsmith/python/managed-deep-agents-identity.md) | memory-sandbox |
| 让 agent 按 cron 自己跑 | [Schedules](https://docs.langchain.com/langsmith/python/managed-deep-agents-schedules.md) | channels-schedule |
| 消息从外部进来、回复发回去 | [Channels](https://docs.langchain.com/langsmith/python/managed-deep-agents-channels.md) | channels-schedule |
| 接到 Slack | [Slack](https://docs.langchain.com/langsmith/python/managed-deep-agents-channels-slack.md) | channels-schedule |
| 接任意 webhook 型外部系统 | [HTTP](https://docs.langchain.com/langsmith/python/managed-deep-agents-channels-http.md) | channels-schedule |
| 跑着跑着停下来问用户要一个答案 | [Agent-owned interrupts](https://docs.langchain.com/langsmith/python/managed-deep-agents-agent-owned-interrupts.md) | channels-schedule |
| 判断"这句该信 context 还是 principal" | [Runtime](https://docs.langchain.com/langsmith/python/managed-deep-agents-runtime.md) | delivery |
| 记住 `mda` 有哪些子命令和参数 | [CLI reference](https://docs.langchain.com/langsmith/python/managed-deep-agents-cli.md) | delivery |
| 部署前在本地调、看 trace | [Local development](https://docs.langchain.com/langsmith/python/managed-deep-agents-local-development.md) | delivery |
| 推到 LangSmith 上跑起来 | [Deploy](https://docs.langchain.com/langsmith/python/managed-deep-agents-deploy.md) | delivery |
| 理解指令/技能/记忆到底存在哪 | [Context Hub](https://docs.langchain.com/langsmith/python/managed-deep-agents-context-hub.md) | delivery |
| 上线前跑评估 | [Evals](https://docs.langchain.com/langsmith/python/managed-deep-agents-evals.md) | delivery |
| 让别的 MCP 客户端把这个 agent 当工具调 | [MCP endpoint](https://docs.langchain.com/langsmith/python/managed-deep-agents-mcp-endpoint.md) | delivery |
| 自己写一个前端来调这个部署 | [Custom frontend](https://docs.langchain.com/langsmith/python/managed-deep-agents-custom-frontend.md) | delivery |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 5 | 总览 / 快速开始 / 项目结构 / 迁移 / 综合教程 |
| capability | [topics/capability.md](./topics/capability.md) | 8 | 定义 / 指令 / 技能 / 工具 / 内置检索 / 连接 / MCP 连接器 / 中间件 |
| memory-sandbox | [topics/memory-sandbox.md](./topics/memory-sandbox.md) | 3 | 记忆 / 沙箱 / 身份 |
| channels-schedule | [topics/channels-schedule.md](./topics/channels-schedule.md) | 5 | 通道总览 / Slack / HTTP / 主动中断 / 调度 |
| delivery | [topics/delivery.md](./topics/delivery.md) | 8 | 运行时 / CLI / 本地开发 / 部署 / Context Hub / 评估 / MCP 端点 / 自定义前端 |
| 合计 | | **29** | |

## 版本要点（写课时先看这里，别现场翻）

| 变更 / 事实 | 内容 | 影响课程 |
|---|---|---|
| 记忆默认关闭 | "Managed Deep Agents **do not have durable memory by default**"，两层都要显式 `define_memory` 才开 | 课 6 |
| 工具与中间件不自动发现 | 官方明确 "MDA does not discover them automatically"，必须 import 后传进定义；对比 instructions / skills 是自动发现的 | 课 4、课 5 |
| 沙箱与 permissions 互斥 | 声明 `sandbox/` 会把 `permissions` 清空；源码两处 `merged["permissions"] = []` 静默发生，build 零提示 | 课 6 |
| `context` 不可作鉴权 | 官方在 runtime 页把 runtime 分四块：context / server info（verified caller）/ channel / sandbox。鉴权只认后者 | 课 7 |
| `mda deploy` 会建 cron | "`mda deploy` provisions each schedule as a LangSmith cron **after the deployment is live**"——调度不是声明完就生效 | 课 8、课 9 |
| 每个部署自带 `/mcp` | 部署跑在 Agent Server 上，因此天然暴露 MCP 端点，无需额外配置 | 课 9 |
| 部署会同步 Context Hub | 部署链路 = 编译 → 同步 deploy-owned context 到 Context Hub → 上传源码 → 触发云端构建；冲突就在这里发生 | 课 9 |
| evals 是 Harbor 任务 | "MDA evals are **Harbor tasks**"，`mda evals init` 只是起手，不是内置评测器 | 课 9 |

## 本课程未使用的两页

| 页面 | 为什么没进正文 |
|---|---|
| [tutorial](https://docs.langchain.com/langsmith/python/managed-deep-agents-tutorial.md) | 是 quickstart 的续篇（把内置搜索换成 Tavily 工具 + 加记忆 + 加日程），与本课程"应用实战"四篇覆盖面重叠，正文不重复收纳。想加练可单独走一遍 |
| [custom-frontend](https://docs.langchain.com/langsmith/python/managed-deep-agents-custom-frontend.md) | 属 UI 集成，超出本课程「agent 怎么组织、平台怎么跑」的边界，仅在课 9 定位级提及 |

## 维护说明

- 重建命令思路：抓 `https://docs.langchain.com/_llms/agent-development-lifecycle/build/python.txt`，`grep "managed-deep-agents"` 即得全部 29 条（比 sitemap 准，且自带官方标题）
- 页面正文取法：URL 末尾加 `.md` 直接返回 Markdown（官网支持）
- 本索引不镜像正文，仅存路由；「一句话」列的措辞一律取自该页官方副标题（`>` 引用行），不是自己概括
