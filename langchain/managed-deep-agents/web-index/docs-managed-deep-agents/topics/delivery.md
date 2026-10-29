# delivery · 运行与交付（8 条）

> 范围：运行时字段、CLI、本地开发、部署、Context Hub、评估、MCP 端点、自定义前端
> 课程落点：课 7、课 9

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Runtime | https://docs.langchain.com/langsmith/python/managed-deep-agents-runtime.md | Read run context, the verified caller, the channel delivery, and the sandbox from the native runtime types | 课 4、课 7 |
| 2 | CLI reference | https://docs.langchain.com/langsmith/python/managed-deep-agents-cli.md | Reference for mda commands, project files, and deploy behavior | 课 1、课 3、课 9 |
| 3 | Local development | https://docs.langchain.com/langsmith/python/managed-deep-agents-local-development.md | Run and test locally with mda dev and LangSmith Studio | 课 1、课 3 |
| 4 | Deploy | https://docs.langchain.com/langsmith/python/managed-deep-agents-deploy.md | Test and deploy with the mda CLI | 课 9 |
| 5 | Context Hub | https://docs.langchain.com/langsmith/python/managed-deep-agents-context-hub.md | How MDA stores instructions, skills, and durable memory in LangSmith Context Hub | 课 2、课 4、课 9 |
| 6 | Evals | https://docs.langchain.com/langsmith/python/managed-deep-agents-evals.md | Develop Harbor evals with a coding agent and the eval-engineering skill | 课 9 |
| 7 | MCP endpoint | https://docs.langchain.com/langsmith/python/managed-deep-agents-mcp-endpoint.md | Expose a deployed agent as a tool to MCP clients such as Claude Code | 课 9 |
| 8 | Custom frontend | https://docs.langchain.com/langsmith/python/managed-deep-agents-custom-frontend.md | Call a deployment from your own browser or server application | 课 9（定位级） |

## 关键结论备忘

- **runtime 页是本课程最重要的单页**：它把 runtime 拆成 context / server info（verified caller）/ channel / sandbox 四块。官方原话是"the native LangChain or LangGraph runtime **with three managed fields added**"——原生能力照旧，托管只加字段
- **context 与 server info 的信任级别不同**：context 是"传进来的"，server info 是"验过的"。这条是课 7 全部判断规则的文档根
- **部署链路四步**（官方原话拆解）：编译成 managed LangGraph app → 把 deploy-owned context 同步到 Context Hub → 上传编译产物 → 触发 LangSmith 托管构建。**Context Hub 冲突就发生在第二步**
- **部署的产物是 Agent Server 部署**：因此自带 Agent Server API 与 `/mcp` 端点；MCP 端点不是额外功能，是部署形态的副产品
- **Context Hub 的分工**：指令/技能/记忆存 Hub，但"项目仍是长期指令与技能更新的 source of truth"——所以改 Hub 不改项目会在下次部署被覆盖
- **evals 是 Harbor task**：`mda evals init` 只是把工作区起好，真正的评测任务是 Harbor 任务，需要配额
- **custom-frontend 只到定位级**：本课程明确不讲 UI 集成，页面列出来是为了让读者知道"接前端"有官方路径
