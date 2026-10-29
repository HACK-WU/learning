# get-started · 入门与定位（5 条）

> 范围：`/langsmith/python/managed-deep-agents*` 下的定位与起跑类页面
> 用法：先看本表定位页面，再打开 URL 取正文
> 课程落点：阶段 1（课 1-3）为主

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Managed Deep Agents | https://docs.langchain.com/langsmith/python/managed-deep-agents-overview.md | Build your agent as a directory of files while LangSmith runs the harness and runtime | 课 2 |
| 2 | Quickstart | https://docs.langchain.com/langsmith/python/managed-deep-agents-quickstart.md | Create and deploy your first Managed Deep Agent with the mda CLI | 课 1、课 3 |
| 3 | Project structure | https://docs.langchain.com/langsmith/python/managed-deep-agents-project-structure.md | Understand the project layout；一个必需根入口 + 其余是被发现的文件/目录 | 课 2、课 3 |
| 4 | Move from Deep Agents | https://docs.langchain.com/langsmith/python/managed-deep-agents-migrate.md | Convert an agent built with create_deep_agent into a Managed Deep Agents project | 课 2、课 9 |
| 5 | Tutorial（加练） | https://docs.langchain.com/langsmith/python/managed-deep-agents-tutorial.md | Replace provider search with a Tavily tool, then add durable memory and a daily schedule | 正文未用，见主索引说明 |

## 关键结论备忘

- **MDA 不是新框架**：官方原话 "MDA runs it. There are no servers to run and no infrastructure to wire together"——它卖的是"托管掉 harness 与 runtime"，harness 仍是 Deep Agents
- **项目结构的分野**：官方说 "one required root agent entry. Other paths are either ordinary modules you import, or files and directories that MDA discovers"。这条区分是课 2「定义与编译分离」的文档依据
- **迁移是重新打包、不是重写**："moving an existing agent is a repackaging job rather than a rewrite. Your tools, middleware, and subagents carry over as they are"
- **迁移时真正变的东西**：入口变了，且 system prompt / skills / memory 从代码迁到项目文件
- **tutorial 页的定位**：它是 quickstart 的续篇，不是独立能力页；本课程应用实战四篇已覆盖同类实操，故正文不重复收纳
