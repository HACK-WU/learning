# 扩展：Stream 高阶能力

> 前置：主课课 5《队列与消息的属性》、课 8《交付语义与幂等》；生产运维专项课 5（监控）完成后再做容量与告警实验。

## 这篇扩展解决什么问题

主课已经说明：Stream 是 append-only、消费后不删除、可按 offset 回放的日志型队列；AMQP `basic.consume` 可以做普通实时消费，而 `basic.get` 不支持。此篇只扩展**为什么要切换到专用 Stream 协议，以及切换后新增了什么能力**。

## 能力边界

| 能力 | 普通 AMQP 0-9-1 | Stream 专用协议 |
|------|:---:|:---:|
| 把 Stream 当普通队列实时消费 | ✅ `basic.consume` | ✅ |
| `basic.get` | ❌ | 不适用 |
| 按 offset 从头 / 指定位置回放 | 受限 | ✅ |
| 流过滤、批量确认、消费者偏移管理 | 不是主路径 | ✅ |
| 仍然使用 TTL、优先级、死信等普通队列特性 | Stream 本身不支持 | Stream 本身不支持 |

## 先做选择，再写代码

适合引入专用协议的信号：

- 同一份事件需要被多个独立消费者各自从不同位置读取；
- 需要新消费者从历史 offset 开始重放，而不是只接收当前消息；
- 事件保留与消费进度是两个独立生命周期。

不适合的信号：

- 只是想要一个“更大的普通队列”；
- 业务依赖 TTL、优先级、死信或按消息拒绝重试；
- 团队没有能力维护第二套客户端、端口和监控路径。

## 最小实操路线（待补实测）

1. 启用 `rabbitmq_stream` 插件并暴露 5552。
2. 用 AMQP `basic.consume` 与专用 Stream 客户端各读一次，确认两条路径的语义差异。
3. 发布 3 条事件，分别从 first / next offset 启动两个消费者。
4. 验证 retention、消费者偏移和重连后的行为。
5. 清理实验队列、插件和端口映射，并记录版本与客户端版本。

## 官方入口

- [Stream plugin](https://www.rabbitmq.com/docs/stream)
- [Stream connections](https://www.rabbitmq.com/docs/stream-connections)
- [Stream filtering](https://www.rabbitmq.com/docs/stream-filtering)
- [Effectively-once processing](https://www.rabbitmq.com/docs/stream-effectively-once-processing)
- [Monitoring](https://www.rabbitmq.com/docs/monitoring)

> 这篇扩展目前完成了边界和路由，专用协议的完整实验待生产运维子教程主体完成后补齐。
