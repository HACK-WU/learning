"""kafka-python-ng 生产者/消费者吞吐基准。

参数与 bench_confluent.py 逐项语义等价：
  acks='all'          <-> acks=all
  linger_ms           <-> linger.ms
  batch_size          <-> batch.size
  max_request_size    <-> fetch.max.bytes（消费侧对应）
用法：python bench_kafka_python.py <round>
"""

import sys
import time

from kafka import KafkaConsumer, KafkaProducer
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError

from common import (
    ACKS, BATCH_SIZE, BOOTSTRAP, COMPRESSION, LINGER_MS,
    MSG_SIZE, NUM_MESSAGES, NUM_PARTITIONS, REPLICATION_FACTOR,
    payload, topic_name,
)

LIB = "kafkapython"


def ensure_topic(topic: str) -> None:
    admin = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, request_timeout_ms=15000)
    try:
        admin.delete_topics([topic], timeout_ms=15000)
        time.sleep(1)
    except Exception:
        pass  # 主题不存在，忽略
    try:
        admin.create_topics(
            [NewTopic(topic, num_partitions=NUM_PARTITIONS,
                      replication_factor=REPLICATION_FACTOR)],
            timeout_ms=15000,
        )
    except TopicAlreadyExistsError:
        pass
    admin.close()


def run_producer(topic: str) -> tuple[float, float]:
    # 注意：kafka-python 的 compression_type 不接受字符串 "none"，
    # 传 None 才表示不压缩（传 "none" 会抛 ValueError: Not supported codec）
    producer = KafkaProducer(
        bootstrap_servers=BOOTSTRAP,
        acks=ACKS,
        compression_type=None if COMPRESSION == "none" else COMPRESSION,
        linger_ms=LINGER_MS,
        batch_size=BATCH_SIZE,
        # 注意：kafka-python 3.0.11 没有 buffer_memory / total_memory 这类配置
        # （早期版本与 kafka-python-ng 曾支持，3.0.11 已移除）。
        # 纯 Python 客户端靠 accumulator 的 deque 累积，无内存上限参数，
        # 因此不会像 confluent 那样因队列满抛 BufferError。
        max_block_ms=60000,
    )

    delivered = [0]

    def on_send(record_metadata):
        delivered[0] += 1

    def on_error(excp):
        raise RuntimeError(f"delivery failed: {excp}")

    start = time.perf_counter()
    for i in range(NUM_MESSAGES):
        producer.send(topic, value=payload(i)).add_callback(
            on_send).add_errback(on_error)
    producer.flush()
    elapsed = time.perf_counter() - start

    assert delivered[0] == NUM_MESSAGES, (
        f"只确认了 {delivered[0]}/{NUM_MESSAGES} 条，结果不可信")

    rate = NUM_MESSAGES / elapsed
    mbps = rate * MSG_SIZE / 1024 / 1024
    return rate, mbps


def run_consumer(topic: str) -> tuple[float, float]:
    consumer = KafkaConsumer(
        topic,
        bootstrap_servers=BOOTSTRAP,
        group_id=f"{LIB}-cg-{int(time.time())}",
        auto_offset_reset="earliest",
        enable_auto_commit=False,
        # 与 confluent 的 fetch.max.bytes 语义对应
        max_partition_fetch_bytes=10 * 1024 * 1024,
        fetch_max_bytes=50 * 1024 * 1024,
        consumer_timeout_ms=30000,
    )

    received = 0
    start = time.perf_counter()
    for _ in consumer:
        received += 1
        if received >= NUM_MESSAGES:
            break
    elapsed = time.perf_counter() - start
    consumer.close()

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
