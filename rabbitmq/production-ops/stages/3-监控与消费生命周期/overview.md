# 阶段 3：监控与消费生命周期

> **故事章节：故障不是“有没有报警”，而是能不能在消息堆满前做出动作。**

本阶段把指标、日志、告警、消费者取消通知、优雅排空和资源上限连成一条处置链。

| 课程 | 回答的问题 | 状态 |
|------|------------|------|
| 课 5 | 哪些信号能证明 broker 或消费链路正在恶化？ | ⬜ |
| 课 6 | 消费者被 broker 取消或需要下线时，如何不丢消息地恢复？ | ⬜ |

官方入口：[monitoring](https://www.rabbitmq.com/docs/monitoring) · [prometheus](https://www.rabbitmq.com/docs/prometheus) · [consumer-cancel](https://www.rabbitmq.com/docs/consumer-cancel) · [consumer-priority](https://www.rabbitmq.com/docs/consumer-priority)
