# memory-sandbox · 记忆、沙箱与身份（3 条）

> 范围：跨会话状态、隔离执行环境、调用方身份——三件互相牵连的事
> 课程落点：课 6 为主，课 7 补充

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Add memory | https://docs.langchain.com/langsmith/python/managed-deep-agents-memory.md | Opt in to durable agent and user memory layers；**默认没有持久记忆** | 课 6、课 7 |
| 2 | Add a sandbox | https://docs.langchain.com/langsmith/python/managed-deep-agents-sandboxes.md | Configure an isolated filesystem and shell | 课 6、课 7 |
| 3 | Add identity | https://docs.langchain.com/langsmith/python/managed-deep-agents-identity.md | Authenticate callers with a LangSmith API key, Supabase, another JWT provider, or your own backend | 课 5、课 6、课 7 |

## 关键结论备忘

- **默认关闭是设计要求，不是疏漏**：官方原话 "Normally, a managed deep agent's conversational memory is scoped to a thread or session. Durable memory is optional knowledge... **Managed Deep Agents do not have durable memory by default.**" 这解释了两层记忆为何都要显式 `define_memory`
- **两层记忆的语义差**：agent 层是"这个 agent 知道的"，user 层是"这个人告诉过它的"；跨层即跨信任域，所以 user 层的默认策略是拒绝
- **沙箱与 permissions 的互斥**：声明 `sandbox/` 会清空 `permissions`（源码两处 `merged["permissions"] = []`，build 零提示）。要"既能跑命令又限制路径"就得另找办法——这是课 6 的核心权衡
- **identity 是四选一**：LangSmith API key / Supabase / 自定义 JWT provider / 自己的 backend。`auth="backend"` 可在本地无 LangSmith key 时启动
- **身份与上下文的分工**：identity 解决"谁在调用"，runtime 页解决"我该信哪一句"；本分区只给声明方法，判断规则在课 7
