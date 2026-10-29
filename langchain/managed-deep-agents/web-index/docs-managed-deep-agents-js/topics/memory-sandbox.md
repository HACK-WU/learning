# memory-sandbox · 记忆、沙箱与身份（3 条 · TS 版）

> 范围：跨会话状态、隔离执行环境、调用方身份
> 对应 Python 版：[../../docs-managed-deep-agents/topics/memory-sandbox.md](../../docs-managed-deep-agents/topics/memory-sandbox.md)
> 课程落点：课 6 为主，课 7 补充

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Add memory | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-memory.md | Opt in to durable agent and user memory layers；**默认没有持久记忆** | 课 6、课 7 |
| 2 | Add a sandbox | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-sandboxes.md | Configure an isolated filesystem and shell | 课 6、课 7 |
| 3 | Add identity | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-identity.md | Authenticate callers with a LangSmith API key, Supabase, another JWT provider, or your own backend | 课 5、课 6、课 7 |

## 与 Python 版的写法差异（本分区）

本分区是两侧差异最集中的地方，**同版本号 ≠ 同 API 面**：

| 点 | Python | TypeScript |
|---|---|---|
| 记忆工厂 | `define_memory(...)` | `defineMemory<Context>({...})`（显式泛型） |
| 记忆层 | `memory_layer(...)` | `memoryLayer<Context>({...})` |
| `allow` 参数类型 | `Callable[[ContextT], bool \| Awaitable[bool]] \| None` | `(context: ManagedRunContext<Context>) => ...`，即 `Context \| ManagedChannelContext` **联合类型** |
| `allow` 废弃状态 | **无 `@deprecated`**（`define_memory.py:46` 实测） | **已标 `@deprecated`**，"Select memory from a dynamic agent definition instead" |
| 沙箱工厂 | `define_sandbox(...)` | `defineSandbox(...)` |

- TS 侧写 `allow` 必须先收窄联合类型（如 `"remember" in context && context.remember === true`），否则类型不过；Python 侧不需要
- 沙箱与 `permissions` 互斥这条**两侧一致**，都是静默清空
- 本分区 3 页标题与 Python 侧逐条相同（2026-10-28 实测 diff 为空）
