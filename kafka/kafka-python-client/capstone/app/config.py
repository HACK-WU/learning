"""课 13 结课实战 —— 配置层。

对应课程：
  - 课 3  AdminClient 与元数据治理（topic 声明、幂等建 topic）
  - 课 7  吞吐调优与压缩（linger / batch / compression）
  - 课 6  确认语义与幂等（acks / enable.idempotence）
  - 课 12 可观测（statistics.interval.ms / stats_cb）

设计原则：所有可调参数集中一处，且每个参数都标注「来自哪一课、为什么是这个值」。
生产里最忌讳的是"这个参数是谁加的、为什么是 100 而不是 10"说不清。
"""

from __future__ import annotations

import os

BROKERS = os.getenv("KAFKA_BROKERS", "kafka-1:9092,kafka-2:9092,kafka-3:9092")
SCHEMA_REGISTRY = os.getenv("SCHEMA_REGISTRY_URL", "http://l9-sr:8081")

TOPIC_ORDERS = os.getenv("TOPIC_ORDERS", "capstone-orders")
TOPIC_DLQ = os.getenv("TOPIC_DLQ", "capstone-orders-dlq")
GROUP_ID = os.getenv("GROUP_ID", "capstone-svc")

NUM_PARTITIONS = 4
REPLICATION_FACTOR = 1  # 单机 3 节点练习集群用 1；生产应 >=3


def producer_conf() -> dict:
    """生产者配置。

    每个非常规值都标注了出处，避免"照抄调优博客但不知所以"。
    """
    return {
        "bootstrap.servers": BROKERS,
        # —— 课 6：确认语义与幂等 ——
        # acks=all + idempotence 是"不丢不重"的最小组合。
        # 注意：开启幂等后 max.in.flight 会被 librdkafka 自动限制到 <=5，
        # 不要再手动设成 100（课 6 实测过：设了会被静默压回 5）。
        "acks": "all",
        "enable.idempotence": True,
        # —— 课 7：吞吐调优 ——
        # linger.ms：攒批窗口。5ms 是延迟与吞吐的折中（课 7 实测曲线）。
        # 设 0 = 每条单发，吞吐掉一个数量级；设 1000 = 延迟不可接受。
        "linger.ms": 5,
        "batch.num.messages": 10000,
        "compression.type": "lz4",  # 课 7 横评：lz4 吞吐/CPU 比最优
        # —— 生产者可靠性 ——
        # 消息在队列里的存活上限；超时触发 delivery 失败回调。
        "message.timeout.ms": 30000,
        # —— 课 12：可观测 ——
        "statistics.interval.ms": 1000,
        # 坑提醒（课 3 同构）：不要用 queue.buffering.max.messages 把内存撑爆，
        # 默认 100000 条已经不小，调大只是把 OOM 延后。
    }


def consumer_conf() -> dict:
    """消费者配置。

    与生产者刻意不同的一处：**关闭自动提交**（课 6 / 课 10）。
    自动提交会在「处理完成前」就提交位移，进程崩溃 => 消息丢失。
    本课用手动提交，且在业务逻辑成功之后才提交。
    """
    return {
        "bootstrap.servers": BROKERS,
        "group.id": GROUP_ID,
        # —— 课 6：手动提交 ——
        "enable.auto.commit": False,
        # —— 课 10：消费者工程 ——
        # 从最早开始，保证冷启动不漏消息；生产新组可按业务选 latest
        "auto.offset.reset": "earliest",
        # 单次 poll 最大条数。设小一点能让 rebalance 更快收敛（课 12 相关）
        "max.poll.records": 500,
        # —— 优雅退出（本课核心能力之一）——
        # session.timeout.ms 决定了 broker 多久判定你"死掉"。
        # 45s 给优雅退出留足时间；太短会导致处理长任务时被误踢出组。
        "session.timeout.ms": 45000,
        # —— 课 12：可观测 ——
        "statistics.interval.ms": 1000,
    }


def admin_conf() -> dict:
    return {"bootstrap.servers": BROKERS}
