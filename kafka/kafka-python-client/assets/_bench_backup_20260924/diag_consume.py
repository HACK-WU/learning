"""诊断：confluent 消费侧为何只跑出 400 msg/s。

假设 A：订阅后未分配到分区，consume() 空转超时
假设 B：分配到分区但拉取被 fetch.wait.max.ms 拖慢
假设 C：消息确实已在上游被消费组读过（位移不在 earliest）
"""

import time

from confluent_kafka import Consumer

BOOTSTRAP = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
TOPIC = "bench-confluent-r1"


def main() -> None:
    consumer = Consumer({
        "bootstrap.servers": BOOTSTRAP,
        "group.id": f"diag-{int(time.time() * 1000)}",
        "auto.offset.reset": "earliest",
        "enable.auto.commit": False,
        "fetch.max.bytes": 50 * 1024 * 1024,
    })
    consumer.subscribe([TOPIC])

    for i in range(6):
        msg = consumer.poll(1.0)
        if msg is None:
            print(f"poll#{i}: None")
            continue
        if msg.error():
            print(f"poll#{i}: error {msg.error()}")
            continue
        print(f"poll#{i}: got msg offset={msg.offset()} "
              f"partition={msg.partition()}")
        break

    print("--- assignment ---")
    print(consumer.assignment())

    print("--- consume(10000, 5s) timing ---")
    t0 = time.perf_counter()
    msgs = consumer.consume(num_messages=10000, timeout=5.0)
    t1 = time.perf_counter()
    print(f"got {len(msgs)} msgs in {t1 - t0:.2f}s")

    consumer.close()


if __name__ == "__main__":
    main()
