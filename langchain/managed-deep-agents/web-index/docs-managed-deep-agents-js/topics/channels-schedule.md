# channels-schedule · 通道与调度（5 条 · TS 版）

> 范围：消息怎么进得来、到点怎么自己跑、跑着怎么停下来问人
> 对应 Python 版：[../../docs-managed-deep-agents/topics/channels-schedule.md](../../docs-managed-deep-agents/topics/channels-schedule.md)
> 课程落点：课 8 为主

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Connect to channels | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-channels.md | Connect MDA to external messaging services that can start runs and receive responses | 课 8 |
| 2 | Slack | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-channels-slack.md | Start runs from Slack messages and send responses to Slack conversations | 课 8 |
| 3 | HTTP | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-channels-http.md | Start runs from any external service that can send a webhook, and return responses through your own transport | 课 8 |
| 4 | Agent-owned interrupts | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-agent-owned-interrupts.md | Post a Slack form from a tool, pause the run, and resume it when the user submits the form | 课 8 |
| 5 | Add schedules | https://docs.langchain.com/langsmith/javascript/managed-deep-agents-schedules.md | Declare managed cron schedules, or create them at runtime | 课 8、课 9 |

## 与 Python 版的写法差异（本分区）

- **通道声明**：TS 用 `channels.slack({ name, ... })` 之类的工厂对象拼装，Python 是 `channels.slack(name=...)` 关键字调用
- **`verify` / `parse` 的校验强度**：本课程实测 TS 侧只校验 `provider` 必须是非空字符串，其余静默放过；同一包内校验强度并不一致，不能按"定义期就会拦住"来推断
- **调度声明层没有 `new_thread`**：这条两侧一致。持久话题在两侧都要写 `thread={"mode":"persistent", "id": ...}` 这类结构
- **`interrupt()` 的调用位置**：两侧都是在工具内部调，由平台把答案转成 `user_prompt_response` 通道事件送回来
- 本分区 5 页标题与 Python 侧逐条相同（2026-10-28 实测 diff 为空）
