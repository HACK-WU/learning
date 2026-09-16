# Apache Kafka 运维文档 · 聚焦索引

> 起始 URL：[https://kafka.apache.org/43/](https://kafka.apache.org/43/) · 生成日期：2026-09-16 · 范围：运维 / 配置 / 安全 / 升级 / 跨机房 · 条目数：33 · 一次性快照
> 只索引不镜像：需要正文时打开对应官方 URL；本表只回答“运维者该去哪一页”。

## 怎么用

1. 先按“我要…”定位任务。
2. 再打开对应官方页面核对版本、参数、默认值和命令。
3. 页面大面积失效时，回到父教程索引与官方 Operations 总览重新核对。

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 做 Topic、分区和重分配等日常操作 | [Basic Kafka Operations](https://kafka.apache.org/43/operations/basic-kafka-operations/) | operations |
| 查监控指标、JMX 与正常值 | [Monitoring](https://kafka.apache.org/43/operations/monitoring/) | operations |
| 查 KRaft Controller 与仲裁运维 | [KRaft](https://kafka.apache.org/43/operations/kraft/) | operations |
| 规划滚动升级 | [Upgrading](https://kafka.apache.org/43/getting-started/upgrade/) | change |
| 规划跨机房镜像与恢复 | [Geo-Replication](https://kafka.apache.org/43/operations/geo-replication-cross-cluster-data-mirroring/) | operations |
| 给运行中的集群接入安全 | [Incorporating Security Features](https://kafka.apache.org/43/security/incorporating-security-features-in-a-running-cluster/) | security |

## 分区索引

| 分区 | 文件 | 覆盖内容 |
|------|------|----------|
| operations | [topics/operations.md](./topics/operations.md) | 日常操作、监控、KRaft、硬件、Java、跨机房、分层存储 |
| configuration | [topics/configuration.md](./topics/configuration.md) | Broker、Topic、Admin、MirrorMaker、分层存储配置 |
| security | [topics/security.md](./topics/security.md) | Listener、TLS/SASL、ACL、在线接入安全、升级 |

## 课程映射

| 课程 | 首要官方分区 |
|------|--------------|
| 课 1–2 | operations + configuration |
| 课 3–5 | operations + configuration |
| 课 6–7 | operations |
| 课 8 | security + change |
| 课 9 | operations + configuration |
