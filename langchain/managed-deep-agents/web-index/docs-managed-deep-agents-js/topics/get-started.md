# get-started · 入门与定位（5 条 · TS 版）

> 范围：`/langsmith/javascript/managed-deep-agents*` 下的定位与起跑类页面
> 对应 Python 版：[../../docs-managed-deep-agents/topics/get-started.md](../../docs-managed-deep-agents/topics/get-started.md)
> 课程落点：阶段 1（课 1-3）

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Managed Deep Agents | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-overview.md | Build your agent as a directory of files while LangSmith runs the harness and runtime | 课 2 |
| 2 | Quickstart | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-quickstart.md | Create and deploy your first Managed Deep Agent with the mda CLI | 课 1、课 3 |
| 3 | Project structure | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-project-structure.md | Understand the project layout | 课 2、课 3 |
| 4 | Move from Deep Agents | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-migrate.md | Convert an agent built with create_deep_agent into a Managed Deep Agents project | 课 2、课 9 |
| 5 | Tutorial（加练） | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-tutorial.md | Add a custom search tool, memory, and a schedule | 正文未用 |

## 与 Python 版的写法差异（本分区）

- `quickstart` 的入口写法不同：Python 是 `define_deep_agent(name=..., model=...)`，TS 是 `defineDeepAgent({ name, model })` 单对象
- `project-structure` 的目录约定两侧一致（`agent.ts` / `instructions.md` / `skills/` / `tools/` / `mcp.json` 等），差的是文件扩展名与导入语法
- `migrate` 页两侧都在讲"重新打包而非重写"，但 TS 侧的现有 agent 来自 `createDeepAgent`，不是 `create_deep_agent`
- 本分区 5 页标题与 Python 侧逐条相同（2026-10-28 实测 diff 为空）
