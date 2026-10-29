# Managed Deep Agents Docs 网页索引（docs.langchain.com · TypeScript 版）

> 起始 URL：https://docs.langchain.com/langsmith/javascript/managed-deep-agents-overview
> 生成日期：2026-10-28 · 范围（scope）：`/langsmith/javascript/managed-deep-agents*` · 条目数：29 · 一次性快照
> 版本基线：`managed-deepagents@0.9.5`（npm）· 核对于 2026-10
> 数据来源：官方 `llms.txt` 索引树（`_llms/agent-development-lifecycle/build/type-script.txt`）逐条提取，29 条 URL 全部实测 HTTP 200
> 只索引不镜像：需要正文时打开对应 URL 取细节

## 怎么用

1. 课程主线是 Python，**同一能力优先读 [Python 版索引](../docs-managed-deep-agents/index.md)**
2. 需要 TS 写法、参数名、包导入路径时读本索引
3. 两侧的**行为差异**不写在这里，统一沉淀在 [`playground-ts/API-MAPPING.md`](../../playground-ts/API-MAPPING.md)，避免两处维护
4. 本表是快照，重建方法见文末

## 与 Python 版的对照结论

**页面集合完全一致：29 / 29，标题逐条相同。** 2026-10-28 用官方 `llms.txt` 两侧清单逐条 diff 实测，无一条独有页面。

需要修正的一条旧记录：本教程档案此前的说法是「22/29 页标题完全一致、7 页因语言差异调整」，与本次实测不符，已按 29/29 修正（差异不在页面结构，而在页面内的 API 名与示例代码）。

**实际差异在页面内容里，不在页面清单里**。已抽查确认的三类：

| 维度 | Python | TypeScript |
|---|---|---|
| 工厂函数 | `define_deep_agent(...)` | `defineDeepAgent({...})`（单个对象参数） |
| 包名 | `managed-deepagents`（PyPI） | `managed-deepagents`（npm，同名不同生态） |
| 记忆 | `define_memory(...)` + `memory_layer(...)` | `defineMemory(...)` + `memoryLayer(...)`，且 `memoryLayer({allow})` 已标 `@deprecated`、参数为联合类型 |
| 沙箱 | `define_sandbox(...)` | `defineSandbox(...)` |

> 完整差异表（八条会静默失效的点）见 [`playground-ts/API-MAPPING.md`](../../playground-ts/API-MAPPING.md)，本索引不重复。

## 分区索引

分区分法与 Python 版**完全对齐**，便于左右互查：

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 5 | 总览 / 快速开始 / 项目结构 / 迁移 / 综合教程 |
| capability | [topics/capability.md](./topics/capability.md) | 8 | 定义 / 指令 / 技能 / 工具 / 内置检索 / 连接 / MCP 连接器 / 中间件 |
| memory-sandbox | [topics/memory-sandbox.md](./topics/memory-sandbox.md) | 3 | 记忆 / 沙箱 / 身份 |
| channels-schedule | [topics/channels-schedule.md](./topics/channels-schedule.md) | 5 | 通道总览 / Slack / HTTP / 主动中断 / 调度 |
| delivery | [topics/delivery.md](./topics/delivery.md) | 8 | 运行时 / CLI / 本地开发 / 部署 / Context Hub / 评估 / MCP 端点 / 自定义前端 |
| 合计 | | **29** | |

## 全部 29 页（平铺速查）

URL 前缀统一为 `https://docs.langchain.com/langsmith/javascript/`：

| slug | 官方标题 |
|---|---|
| `managed-deep-agents-overview` | Managed Deep Agents |
| `managed-deep-agents-quickstart` | Managed Deep Agents quickstart |
| `managed-deep-agents-project-structure` | Managed Deep Agents project structure |
| `managed-deep-agents-migrate` | Move from Deep Agents to Managed Deep Agents |
| `managed-deep-agents-agent-definition` | Define a Managed Deep Agent |
| `managed-deep-agents-instructions` | Add instructions to Managed Deep Agents |
| `managed-deep-agents-skills` | Add skills to Managed Deep Agents |
| `managed-deep-agents-tools` | Add custom tools to Managed Deep Agents |
| `managed-deep-agents-search` | Built-in search powered by Parallel |
| `managed-deep-agents-connections` | Manage connections |
| `managed-deep-agents-mcp-connectors` | Connect to MCP servers |
| `managed-deep-agents-middleware` | Add custom middleware to Managed Deep Agents |
| `managed-deep-agents-memory` | Add memory to Managed Deep Agents |
| `managed-deep-agents-sandboxes` | Add a sandbox to Managed Deep Agents |
| `managed-deep-agents-identity` | Add identity to Managed Deep Agents |
| `managed-deep-agents-schedules` | Add schedules to Managed Deep Agents |
| `managed-deep-agents-evals` | Evaluate Managed Deep Agents |
| `managed-deep-agents-runtime` | Managed Deep Agents runtime |
| `managed-deep-agents-channels` | Connect Managed Deep Agents to channels |
| `managed-deep-agents-channels-slack` | Connect a Managed Deep Agent to Slack |
| `managed-deep-agents-channels-http` | Connect a Managed Deep Agent over HTTP |
| `managed-deep-agents-agent-owned-interrupts` | Prompt Slack users with agent-owned interrupts |
| `managed-deep-agents-local-development` | Develop locally with LangSmith Studio |
| `managed-deep-agents-tutorial` | Add a custom search tool, memory, and a schedule |
| `managed-deep-agents-deploy` | Deploy a Managed Deep Agent |
| `managed-deep-agents-mcp-endpoint` | Connect MCP clients to a Managed Deep Agent |
| `managed-deep-agents-custom-frontend` | Build a custom frontend for a Managed Deep Agent |
| `managed-deep-agents-context-hub` | Manage Context Hub for Managed Deep Agents |
| `managed-deep-agents-cli` | Managed Deep Agents CLI reference |

## 版本要点（TS 侧特有，写课时先看）

| 事实 | 内容 | 影响 |
|---|---|---|
| CLI 是同一个 `mda` | npm 包 `bin` 指向 `bin/mda.mjs`，命令名与 Python 侧一致 | 课 1、课 9 |
| 无 peerDependencies | `langchain`、`@langchain/core`、`@langchain/langgraph`、`@langchain/mcp-adapters`、`zod` 全是直接依赖，装一个包即可 | 课 1 |
| `exports` 未开放 `./package.json` | 读版本号不能 `import` 或 `require`，只能 `readFileSync` 相对路径读文件 | playground-ts/l01 |
| 五个托管自有键在运行时硬失败 | `backend` / `store` / `checkpointer` / `systemPrompt` / `disableMemory` 传入会抛错，不只是类型层拦截 | 课 2、课 4 |
| `name` 宽容度与 Python 相反 | TS 允许 const 变量甚至模板字符串，`mda build` 会求值；Python 严格要求字面量 | 课 3 |

## 维护说明

- 重建命令思路：抓 `https://docs.langchain.com/_llms/agent-development-lifecycle/build/type-script.txt`，`grep "managed-deep-agents"` 即得全部 29 条
- 页面正文取法：URL 末尾加 `.md` 直接返回 Markdown
- 与 Python 版做集合比对：两侧标题 diff 为空（29/29），只有内容差异
