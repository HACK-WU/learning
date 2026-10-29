# capability · 能力声明（8 条 · TS 版）

> 范围：把 agent 的能力一件件写成可被发现/可被注册的东西
> 对应 Python 版：[../../docs-managed-deep-agents/topics/capability.md](../../docs-managed-deep-agents/topics/capability.md)
> 课程落点：阶段 2（课 4-5）

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Define a Managed Deep Agent | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-agent-definition.md | Configure the model and core capabilities of a managed deep agent | 课 2、课 3、课 6、课 7 |
| 2 | Add instructions | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-instructions.md | Define the system prompt for a managed deep agent in instructions.md | 课 4 |
| 3 | Add skills | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-skills.md | Add reusable task-specific instructions；自动发现，按 frontmatter 匹配后整份加载 | 课 4 |
| 4 | Add custom tools | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-tools.md | Define authored tools；**不自动发现** | 课 4、课 7 |
| 5 | Built-in search | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-search.md | Add web search powered by Parallel without a separate account or API key | 课 5 |
| 6 | Manage connections | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-connections.md | Store API keys and OAuth grants so MDA can authenticate with external services at runtime | 课 5 |
| 7 | Connect to MCP servers | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-mcp-connectors.md | Add tools from remote MCP servers | 课 5 |
| 8 | Add custom middleware | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-middleware.md | Add built-in or custom middleware；同样**不自动发现** | 课 5 |

## 与 Python 版的写法差异（本分区）

- **工具定义**：TS 用 `tool(async (input, runtime) => {...}, { name, description, schema: z.object({...}) })`，schema 走 zod；Python 用 `@tool(parse_docstring=True)` 装饰器
- **`ManagedToolRuntime` 泛型顺序与 Python 相反**：TS 是 `<TState, TContext>`，Python 是 `[Context, State]`。只写一个参数会把 context 顶到 state 槽，`runtime.context` 塌成 `{}`——本课程 `playground-ts/l07` 有实测
- **`skills` / `mcp` 传错位置时**：TS 侧类型层与运行时都放过，**要到 `mda build` 才拒绝**；Python 侧在定义期就报。这是最容易在本地自测中漏掉的一条
- **中间件导入路径**：TS 侧从 `langchain` 或 `@langchain/langgraph` 取，包内不会替你兜底
- 本分区 8 页标题与 Python 侧逐条相同（2026-10-28 实测 diff 为空）
