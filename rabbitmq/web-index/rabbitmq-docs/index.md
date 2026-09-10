# RabbitMQ Docs 网页索引

> 起始 URL：https://www.rabbitmq.com/docs
> 生成日期：2026-09-10 · 范围（scope）：/docs（当前稳定版，未带版本号路径；已排除 3.13/4.0/4.1/4.2/next 版本快照目录） · 条目数：159 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：本课程基线 RabbitMQ 4.3.5（Docker 实测），Python + pika；文档站为最新稳定版，涉及版本差异的参数（如内存水位、delivery-limit）以课程讲义标注为准

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_rabbitmq-docs_web_index.py` / `web-index-rabbitmq-docs-map-current.md`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 查 publisher confirms（发布方不丢消息的保障） | [confirms](https://www.rabbitmq.com/docs/confirms) | reliability |
| 查 consumer ack/nack/reject/requeue 语义与陷阱 | [nack](https://www.rabbitmq.com/docs/nack) | reliability |
| 查 prefetch 与公平分发（含 consumer_timeout） | [consumer-prefetch](https://www.rabbitmq.com/docs/consumer-prefetch) | reliability |
| 配 TTL 与死信交换机 DLX | [ttl](https://www.rabbitmq.com/docs/ttl) / [dlx](https://www.rabbitmq.com/docs/dlx) | queues |
| 查 quorum 队列参数（x-delivery-limit 等，仅 quorum 支持的项） | [quorum-queues](https://www.rabbitmq.com/docs/quorum-queues) | queues |
| 查 rabbitmqctl 全部子命令 | [man/rabbitmqctl.8](https://www.rabbitmq.com/docs/man/rabbitmqctl.8) | management |
| 处理网络分区（net-split）与 4.x 哑分区策略 | [partitions](https://www.rabbitmq.com/docs/partitions) | clustering |
| 查内存/磁盘告警水位（4.x 默认 0.6）与流控 | [memory](https://www.rabbitmq.com/docs/memory) / [alarms](https://www.rabbitmq.com/docs/alarms) | monitoring |
| 上线前过生产部署检查清单 | [production-checklist](https://www.rabbitmq.com/docs/production-checklist) | production |
| 用 Direct Reply-To 做 RPC（须同连接同信道） | [direct-reply-to](https://www.rabbitmq.com/docs/direct-reply-to) | reliability |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 17 | 文档入口、下载与各平台安装、Erlang 版本对应（人工归并，非站点原结构） |
| concepts | [topics/concepts.md](./topics/concepts.md) | 23 | AMQP 模型：连接/信道/交换机/队列、协议与规范参考、与 Kafka 对比、网络配置 |
| queues | [topics/queues.md](./topics/queues.md) | 15 | classic/quorum/stream、惰性/优先级队列、max-length、TTL 与死信、持久化 |
| reliability | [topics/reliability.md](./topics/reliability.md) | 11 | publisher confirms、ack/nack、prefetch、心跳、快照备份、Direct Reply-To |
| clustering | [topics/clustering.md](./topics/clustering.md) | 13 | 集群搭建、节点发现、节点间 TLS、网络分区、Khepri 元数据存储、feature flags |
| cross-site | [topics/cross-site.md](./topics/cross-site.md) | 7 | Federation（交换机/队列/参数）、Shovel（动态/静态） |
| management | [topics/management.md](./topics/management.md) | 20 | Management UI/HTTP API、rabbitmqadmin、CLI 与 rabbitmqctl 等 man 手册、策略/定义 |
| monitoring | [topics/monitoring.md](./topics/monitoring.md) | 8 | 监控指标、Prometheus、内存与磁盘告警、内存分析、流控、firehose |
| security | [topics/security.md](./topics/security.md) | 19 | 用户/权限/vhost、认证与密码、LDAP、OAuth 2.0（含各 IdP 示例）、TLS |
| plugins | [topics/plugins.md](./topics/plugins.md) | 11 | 插件机制与安装、MQTT/STOMP/Web 系、自定义交换机类型、消息拦截器 |
| production | [topics/production.md](./topics/production.md) | 6 | 生产检查清单、rabbitmq.conf 全解、运行时调优、日志、目录迁移、用户上限 |
| upgrades | [topics/upgrades.md](./topics/upgrades.md) | 5 | 升级总览、滚动/蓝绿/扩缩式升级、废弃特性清单（4.x 移除项） |
| troubleshooting | [topics/troubleshooting.md](./topics/troubleshooting.md) | 4 | 常规/网络/TLS/OAuth2 四类排错页（课程重点，单独成区） |
