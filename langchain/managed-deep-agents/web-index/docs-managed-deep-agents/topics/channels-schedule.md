# channels-schedule · 通道与调度（5 条）

> 范围：消息怎么进得来、到点怎么自己跑、跑着怎么停下来问人
> 课程落点：课 8 为主

| # | 页面 | URL | 一句话（取自官方副标题） | 课程落点 |
|---|------|-----|------------------------|----------|
| 1 | Connect to channels | https://docs.langchain.com/langsmith/python/managed-deep-agents-channels.md | Connect MDA to external messaging services that can start runs and receive responses | 课 8 |
| 2 | Slack | https://docs.langchain.com/langsmith/python/managed-deep-agents-channels-slack.md | Start runs from Slack messages and send responses to Slack conversations | 课 8 |
| 3 | HTTP | https://docs.langchain.com/langsmith/python/managed-deep-agents-channels-http.md | Start runs from any external service that can send a webhook, and return responses through your own transport | 课 8 |
| 4 | Agent-owned interrupts | https://docs.langchain.com/langsmith/python/managed-deep-agents-agent-owned-interrupts.md | Post a Slack form from a tool, pause the run, and resume it when the user submits the form | 课 8 |
| 5 | Add schedules | https://docs.langchain.com/langsmith/python/managed-deep-agents-schedules.md | Declare managed cron schedules, or create them at runtime | 课 8、课 9 |

## 关键结论备忘

- **通道是双向的**：官方定义里既有"消息能起 run"，也有"最终回复从同一个服务回去"；只接一半不算接完
- **Slack 通道做了四件事**（官方原文）：验证 Slack 事件 → 把每个会话映射到一个 thread → 以解析出的调用者身份运行 → 把回复发回 Slack。这解释了为什么线程与身份是绑在一起的
- **HTTP 通道的定位是"兜底"**："Use it for a provider that MDA does not support directly"——订单系统、客服工具、你自己的应用都走这条
- **主动中断和普通人在环中的差别**：中断是**你的代码**创建的暂停（工具里贴 Block Kit 表单后调 `interrupt()`），用户提交后平台以 `user_prompt_response` 通道事件把答案送回并恢复运行。所以它属于通道能力，不是纯图运行时能力
- **调度不是声明完就生效**：官方明确 `mda deploy` 是在部署**上线之后**才把每条 schedule 建成 LangSmith cron
- **`at` 与 `cron` 的默认线程策略相反**（本课程实测补充）：运行时创建时 `cron` 的 `new_thread` 默认 True、`at` 默认 False；声明层则没有 `new_thread` 参数，持久话题要写 `thread={"mode":"persistent",...}`
