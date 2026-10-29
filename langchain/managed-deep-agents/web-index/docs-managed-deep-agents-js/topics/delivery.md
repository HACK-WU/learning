# delivery · 运行与交付（8 条 · TS 版）

> 范围：运行时字段、CLI、本地开发、部署、Context Hub、评估、MCP 端点、自定义前端
> 对应 Python 版：[../../docs-managed-deep-agents/topics/delivery.md](../../docs-managed-deep-agents/topics/delivery.md)
> 课程落点：课 7、课 9

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Runtime | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-runtime.md | Read run context, the verified caller, the channel delivery, and the sandbox from the native runtime types | 课 4、课 7 |
| 2 | CLI reference | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-cli.md | Reference for mda commands, project files, and deploy behavior | 课 1、课 3、课 9 |
| 3 | Local development | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-local-development.md | Run and test locally with mda dev and LangSmith Studio | 课 1、课 3 |
| 4 | Deploy | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-deploy.md | Test and deploy with the mda CLI | 课 9 |
| 5 | Context Hub | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-context-hub.md | How MDA stores instructions, skills, and durable memory in LangSmith Context Hub | 课 2、课 4、课 9 |
| 6 | Evals | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-evals.md | Develop Harbor evals with a coding agent and the eval-engineering skill | 课 9 |
| 7 | MCP endpoint | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-mcp-endpoint.md | Expose a deployed agent as a tool to MCP clients such as Claude Code | 课 9 |
| 8 | Custom frontend | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-custom-frontend.md | Call a deployment from your own browser or server application | 课 9（定位级） |

## 与 Python 版的写法差异（本分区）

- **runtime 字段名**：托管新增的三个字段两侧同名（`context` / `serverInfo` / `channel`，Python 侧是 `context` / `server_info` / `channel`），大小写约定不同
- **`ManagedToolRuntime<TState, TContext>` 是双泛型**，且顺序与 Python `[Context, State]` 相反。只写一个参数时 `runtime.context` 被推成 `{}`，访问自定义字段报 `TS2339`
- **CLI 是同一个 `mda`**：npm 包 `bin` 指向 `bin/mda.mjs`，子命令面与 Python 侧一致（`build` / `dev` / `deploy` / `evals init`）
- **`exports` 未开放 `./package.json`**：想读版本号只能用 `readFileSync` 按相对路径读 `node_modules/managed-deepagents/package.json`
- **部署链路两侧同构**：编译 → 同步 Context Hub → 上传 → 触发云端构建；`mda deploy` / `mda evals` 都需要账号与配额，本课程标 ⚠️ 未实测
- 本分区 8 页标题与 Python 侧逐条相同（2026-10-28 实测 diff 为空）
