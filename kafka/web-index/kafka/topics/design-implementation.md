# design-implementation（Apache Kafka 文档 · 共 12 条）

> 范围：`/43/design/` + `/43/implementation/` · 生成日期：2026-09-10
> 采集自 sitemap 全部 12 条（无裁剪）；每条已实测 HTTP 200
> 这一组是"为什么这样设计"与"底层怎么实现"的权威出处，讲顺序写磁盘 / 零拷贝 / 消息格式时直接 fetch

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 查设计总览入口 | [Design 总览](https://kafka.apache.org/43/design/) | | 设计、架构、动机 | |
| 讲 Kafka 的设计动机与权衡（第 4 课：顺序写/零拷贝） | [Design（官方原文）](https://kafka.apache.org/43/design/design/) | | 设计动机、持久化、效率、零拷贝 | [Log 实现](https://kafka.apache.org/43/implementation/log/) |
| 查 wire protocol 与 API 规范 | [Protocol](https://kafka.apache.org/43/design/protocol/) | | 协议、API、wire format | |
| 查底层实现总入口 | [Implementation 总览](https://kafka.apache.org/43/implementation/) | | 实现、底层 | |
| 讲分区日志结构、顺序写、保留与压实（第 4 课） | [Log 实现（官方原文）](https://kafka.apache.org/43/implementation/log/) | | 日志、分段、顺序写、压实 | |
| 讲分区分配与消费者负载分布机制 | [Distribution](https://kafka.apache.org/43/implementation/distribution/) | | 分区分配、负载均衡 | |
| 讲网络层与请求处理模型（Reactor / 线程模型） | [Network Layer](https://kafka.apache.org/43/implementation/network-layer/) | | 网络层、NIO、线程模型 | |
| 查消息二进制格式（Record / RecordBatch） | [Message Format](https://kafka.apache.org/43/implementation/message-format/) | | 消息格式、二进制、RecordBatch | |
| 查消息与批次的字段语义 | [Messages](https://kafka.apache.org/43/implementation/messages/) | | 消息、批次、字段 | |
| 查当前版长页的设计章节 | [当前版长页 · Design](https://kafka.apache.org/documentation/#design) | `#design` | 设计、当前版 | |
| 查当前版长页的实现章节 | [当前版长页 · Implementation](https://kafka.apache.org/documentation/#implementation) | `#implementation` | 实现、当前版 | |
| 查协议规范（当前版独立页） | [Protocol（顶层）](https://kafka.apache.org/protocol/) | | 协议、规范 | |
