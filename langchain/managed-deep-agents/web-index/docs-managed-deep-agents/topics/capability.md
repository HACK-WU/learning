# capability · 能力声明（8 条）

> 范围：把 agent 的能力一件件写成可被发现/可被注册的东西
> 课程落点：阶段 2（课 4-5）

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Define a Managed Deep Agent | https://docs.langchain.com/langsmith/python/managed-deep-agents-agent-definition.md | Configure the model and core capabilities of a managed deep agent | 课 2、课 3、课 6、课 7 |
| 2 | Add instructions | https://docs.langchain.com/langsmith/python/managed-deep-agents-instructions.md | Define the system prompt for a managed deep agent in instructions.md | 课 4 |
| 3 | Add skills | https://docs.langchain.com/langsmith/python/managed-deep-agents-skills.md | Add reusable task-specific instructions；自动发现，按 frontmatter 描述匹配后整份加载 | 课 4 |
| 4 | Add custom tools | https://docs.langchain.com/langsmith/python/managed-deep-agents-tools.md | Define authored tools；**不像 instructions/skills 那样自动发现** | 课 4、课 7 |
| 5 | Built-in search | https://docs.langchain.com/langsmith/python/managed-deep-agents-search.md | Add web search powered by Parallel without a separate account or API key | 课 5 |
| 6 | Manage connections | https://docs.langchain.com/langsmith/python/managed-deep-agents-connections.md | Store API keys and OAuth grants so MDA can authenticate with external services at runtime | 课 5 |
| 7 | Connect to MCP servers | https://docs.langchain.com/langsmith/python/managed-deep-agents-mcp-connectors.md | Add tools from remote MCP servers；MDA 负责建客户端并加载工具 | 课 5 |
| 8 | Add custom middleware | https://docs.langchain.com/langsmith/python/managed-deep-agents-middleware.md | Add built-in or custom middleware；同样**不自动发现**，必须显式传入 | 课 5 |

## 关键结论备忘

- **自动发现的分界线**（本课程最容易被记错的一点）：instructions 与 skills 自动发现；tools 与 middleware **必须 import 后传进定义**。官方在 tools 页与 middleware 页各写了一遍 "does not discover ... automatically"
- **skills 是渐进披露**："The agent loads a skill's full contents **only when the task matches the description in the frontmatter**"——所以 frontmatter 的 description 写不好，技能等于不存在
- **connections 解决的是凭据，不是配置**：凭据存在你的 LangSmith workspace，运行时用 `connections.get(...)` 取；这解释了为什么 API key 不该写进代码
- **search 是平台送的**：Parallel 驱动的内置搜索，不需要单独账号或 key，与自建 Tavily 工具是两条路
- **定义页是枢纽**：`agent-definition` 被课 2/3/6/7 反复引用，因为模型、mcp、skills、memory 等声明最终都汇到这一处
