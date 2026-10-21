# context-management · 上下文管理（4 条）

> 范围：/oss/python/deepagents 下的上下文类页面
> 一句话定位：agent "知道什么、能撑多久、跨会话留下什么"

| # | 页面 | URL | 一句话 | 课程落点 |
|---|------|-----|--------|----------|
| 1 | Skills | https://docs.langchain.com/oss/python/deepagents/skills.md | 按 Agent Skills 标准，`SKILL.md` + 渐进式披露 | 课 7 |
| 2 | Memory | https://docs.langchain.com/oss/python/deepagents/memory.md | `AGENTS.md` 启动时加载，与 skills 的按需加载相反 | 课 8 |
| 3 | Retrieval | https://docs.langchain.com/oss/python/deepagents/retrieval.md | 检索接入 | 课 9 |
| 4 | Context engineering in Deep Agents | https://docs.langchain.com/oss/python/deepagents/context-engineering.md | 四段上下文流：输入 / 压缩 / 隔离 / 长期记忆 | 课 9 |

## 关键结论备忘

- **Skills vs Memory 的加载时机是反的**：skills 启动时只读 frontmatter、用时才读全文（progressive disclosure）；memory 文件**总是全量加载**
- 记忆内容存放在配置的后端里（`StateBackend` / `StoreBackend` / `FilesystemBackend`）
- agent 可以**自己更新记忆**（基于交互与反馈）
- 上下文四段流：输入上下文（prompt + memory + skills + 工具提示）→ 压缩（卸载 + 摘要）→ 隔离（子代理）→ 长期记忆（虚拟文件系统跨线程）
- **提示缓存只对 Anthropic / Amazon Bedrock 默认开启**，其它 provider 需配 provider 专属缓存中间件
