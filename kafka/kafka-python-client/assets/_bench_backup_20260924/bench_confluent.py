"""confluent-kafka 生产者/消费者吞吐基准。

参数与 kafka_python_bench.py 逐项语义等价，确保对照公平。
用法：python bench_confluent.py <round>
"""

import sys
import time

from confluent_kafka import Consumer, Producer, TopicPartition
from confluent_kafka.admin import AdminClient, NewTopic

from common import (
    ACKS, BATCH_SIZE, BOOTSTRAP, COMPRESSION, LINGER_MS,
    MSG_SIZE, NUM_MESSAGES, NUM_PARTITIONS, REPLICATION_FACTOR,
    payload, topic_name,
)

LIB = "confluent"


def ensure_topic(topic: str) -> None:
    admin = AdminClient({"bootstrap.servers": BOOTSTRAP})
    existing = admin.list_topics(timeout=10).topics
    if topic in existing:
        # future 参数只能按位置传，同时用关键字会 TypeError
        fs = admin.delete_topics([topic], operation_timeout=15)
        fs[topic].result()
        time.sleep(2)
    admin.create_topics(
        [NewTopic(topic, num_partitions=NUM_PARTITIONS,
                  replication_factor=REPLICATION_FACTOR)],
        operation_timeout=15,
    )[topic].result()


def run_producer(topic: str) -> tuple[float, float]:
    conf = {
        "bootstrap.servers": BOOTSTRAP,
        "acks": ACKS,
        "compression.type": COMPRESSION,
        "linger.ms": LINGER_MS,
        "batch.size": BATCH_SIZE,
        # 队列足够大，避免 BufferError 打断计时
        "queue.buffering.max.messages": NUM_MESSAGES * 2,
        "statistics.interval.ms": 0,
    }
    producer = Producer(conf)

    delivered = [0]

    def on_delivery(err, msg):
        if err is not None:
            raise RuntimeError(f"delivery failed: {err}")
        delivered[0] += 1

    start = time.perf_counter()
    for i in range(NUM_MESSAGES):
        producer.produce(topic, value=payload(i), callback=on_delivery)
        # 非阻塞 poll，触发回调与 I/O（不在计时外偷跑）
        producer.poll(0)
    producer.flush()
    elapsed = time.perf_counter() - start

    assert delivered[0] == NUM_MESSAGES, (
        f"只确认了 {delivered[0]}/{NUM_MESSAGES} 条，结果不可信")

    rate = NUM_MESSAGES / elapsed
    mbps = rate * MSG_SIZE / 1024 / 1024
    return rate, mbps


def run_consumer(topic: str) -> tuple[float, float]:
    conf = {
        "bootstrap.servers": BOOTSTRAP,
        "group.id": f"{LIB}-cg-{int(time.time() * 1000)}",
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
        # 一次拉尽可能多的字节，减少往返
        "fetch.max.bytes": 50 * 1024 * 1024,
        "fetch.wait.max.ms": 100,
        "session.timeout.ms": 30000,
    }
    consumer = Consumer(conf)
    consumer.subscribe([topic])

    # 关键：订阅后必须先等待分区分配完成，否则 consume() 会在
    # 尚未 join 组时提前超时返回空，导致速率被严重低估
    # （实测不等待时 2000 条要跑 5 秒 = 400 msg/s）
    deadline = time.time() + 30
    while time.time() < deadline:
        msg = consumer.poll(1.0)
        if msg is not None and not msg.error():
            # seek 只接受 TopicPartition 对象，不接受三元组
            consumer.seek(TopicPartition(msg.topic(), msg.partition(), msg.offset()))
            break

    received = 0
    empty_rounds = 0
    start = time.perf_counter()
    # 关键：confluent 的 consume() 无论是否拿够 num_messages 都会等满 timeout，
    # 因此不能在循环外计时，必须用"拿到最后一条消息"的时刻作为结束点
    # （不修的话会把固定 5 秒等待算进耗时，速率被低估一个数量级）
    last_msg_at = start
    while received < NUM_MESSAGES:
        msgs = consumer.consume(num_messages=10000, timeout=1.0)
        if not msgs:
            empty_rounds += 1
            if empty_rounds >= 3:
                break
            continue
        empty_rounds = 0
        for m in msgs:
            if m.error():
                raise RuntimeError(f"consume error: {m.error()}")
            received += 1
            if received >= NUM_MESSAGES:
                break
        last_msg_at = time.perf_counter()
    elapsed = last_msg_at - start
    consumer.close()

    if received < NUM_MESSAGES:
        raise RuntimeError(
            f"只消费到 {received}/{NUM_MESSAGES} 条，结果不可信")

    rate = received / elapsed
    mbps = rate * MSG_SIZE / 1024 / 1024
    return rate, mbps


def main() -> None:
    # label 形如 "A-none-l10" / "B-zstd-l10" / "C-none-l50"，不再是纯数字轮次
    label = sys.argv[1] if len(sys.argv) > 1 else "default"
    topic = topic_name(LIB, label)
    ensure_topic(topic)
    time.sleep(2)

    prate, pmbps = run_producer(topic)
    crate, cmbps = run_consumer(topic)

    print(f"RESULT {LIB} label={label} "
          f"produce_msg_s={prate:.0f} produce_MB_s={pmbps:.2f} "
          f"consume_msg_s={crate:.0f} consume_MB_s={cmbps:.2f}")


if __name__ == "__main__":
    main()
