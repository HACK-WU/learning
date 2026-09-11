# javadoc（Apache Kafka 文档 · 共 14 条）

> 范围：`/43/javadoc/` · 生成日期：2026-09-10
> Javadoc **不在 sitemap 里**（sitemap 只收文档页），本表按课程第 9 课（代码开发实战）与第 8 课（事务）实际用到的类整理，**每条已实测 HTTP 200**
> 课程用 Python 客户端（kafka-python 3.0.11），但**官方 Javadoc 是语义权威**——Python 客户端的 API 与参数语义与 Java 对齐，查"某参数/异常到底什么意思"时以 Javadoc 为准

| 我要… | 去哪一页 | 关键词 | 相关课程 |
|-------|----------|--------|----------|
| 查 Javadoc 总入口 | [Javadoc Index](https://kafka.apache.org/43/javadoc/index.html) | 入口、API | — |
| 写生产者代码、查幂等与事务官方示例（第 8/9 课） | [KafkaProducer](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/producer/KafkaProducer.html) | 生产者、send、事务 | 课 5、8、9 |
| 查生产者配置项常量 | [ProducerConfig](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/producer/ProducerConfig.html) | 配置常量 | 课 5、8 |
| 构造发送的消息（topic / key / value / partition / headers） | [ProducerRecord](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/producer/ProducerRecord.html) | 消息、record | 课 5、9 |
| 查异步发送回调签名 | [Callback](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/producer/Callback.html) | 回调、异步 | 课 5、9 |
| 写消费者代码、查 poll 循环与位移提交（第 6/9 课） | [KafkaConsumer](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html) | 消费者、poll、offset | 课 6、9 |
| 查消费者配置项常量 | [ConsumerConfig](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/ConsumerConfig.html) | 配置常量 | 课 6 |
| 查一批拉取结果的迭代方式 | [ConsumerRecords](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/ConsumerRecords.html) | 批量、迭代 | 课 6、9 |
| 查单条消息的字段（offset / key / value / timestamp） | [ConsumerRecord](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/ConsumerRecord.html) | 消息字段 | 课 6、9 |
| 查事务提交位移的数据结构（第 8 课 sendOffsetsToTransaction） | [OffsetAndMetadata](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/OffsetAndMetadata.html) | 位移、事务 | 课 8、实战项目 |
| 查 TopicPartition 结构（手动分配分区 / 事务位移） | [TopicPartition](https://kafka.apache.org/43/javadoc/org/apache/kafka/common/TopicPartition.html) | 分区、事务 | 课 8、实战项目 |
| 用 Admin 客户端建 topic / 查元数据 | [Admin](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/admin/Admin.html) | 管理客户端 | 课 3、实战项目 |
| 查僵尸实例围栏异常（事务 epoch 冲突） | [ProducerFencedException](https://kafka.apache.org/43/javadoc/org/apache/kafka/common/errors/ProducerFencedException.html) | 事务、僵尸、epoch | 课 8 |
| 查幂等序列号跳号异常 | [OutOfOrderSequenceException](https://kafka.apache.org/43/javadoc/org/apache/kafka/common/errors/OutOfOrderSequenceException.html) | 幂等、序列号 | 课 8 |
