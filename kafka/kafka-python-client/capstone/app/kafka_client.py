"""课 13 —— Kafka 客户端封装（课 3/6/7/12 能力汇聚）。

这一层刻意保持"薄"：只做三件事
  1. 幂等建 topic（课 3）
  2. 带 delivery 回调的生产（课 6）+ 统计采集（课 12）
  3. lag 采集（课 12，含本课补测的 rebalance 教训）

所有"业务判断"都不放这里，方便分层测试用 fake 替换（课 12 分层测试）。
"""

from __future__ import annotations

import json
import logging
import threading
import time

from confluent_kafka import Consumer, Producer
from confluent_kafka.admin import AdminClient, NewTopic

from . import config, metrics

log = logging.getLogger("capstone.kafka")


# ---------- 1. 幂等建 topic（课 3）----------


def ensure_topics(timeout: float = 15.0) -> dict[str, bool]:
    """确保 topic 存在。已存在则跳过（**不抛异常**）。

    坑（课 3 实测）：create_topics 对已存在 topic 返回 TOPIC_ALREADY_EXISTS 错误，
    直接当失败处理会让服务每次重启都崩。正确做法是"已存在即成功"。
    """
    admin = AdminClient(config.admin_conf())
    wanted = {
        config.TOPIC_ORDERS: (config.NUM_PARTITIONS, config.REPLICATION_FACTOR),
        config.TOPIC_DLQ: (config.NUM_PARTITIONS, config.REPLICATION_FACTOR),
    }
    existing = set(admin.list_topics(timeout=timeout).topics)
    result: dict[str, bool] = {}

    to_create = []
    for name, (parts, rf) in wanted.items():
        if name in existing:
            result[name] = True
            log.info("topic %s 已存在，跳过创建", name)
        else:
            to_create.append(NewTopic(name, num_partitions=parts, replication_factor=rf))
            result[name] = False

    if to_create:
        futures = admin.create_topics(to_create)
        for name, f in futures.items():
            try:
                f.result(timeout=timeout)
                result[name] = True
                log.info("topic %s 创建成功", name)
            except Exception as e:  # noqa: BLE001 - 记录后继续，不阻断启动
                log.warning("topic %s 创建失败: %s", name, e)
                result[name] = False
    return result


# ---------- 2. 生产者（课 6 + 课 7 + 课 12）----------


class OrderProducer:
    """带统计采集的生产者。

    要点（课 6）：
      - 必须 **poll()** 才会触发 delivery 回调。只 produce 不 poll，
        回调永远不执行 —— 这是课 12 测过的"假绿"同源问题。
      - 这里用后台线程定期 poll，模拟真实服务的做法。
    """

    def __init__(self, stats_cb=None):
        conf = config.producer_conf()
        if stats_cb:
            conf["stats_cb"] = stats_cb
        self._p = Producer(conf)
        self._lock = threading.Lock()
        self._poll_thread: threading.Thread | None = None
        self._stop = threading.Event()
        self.delivered = 0
        self.failed = 0
        self.last_error: str | None = None

    def start(self) -> None:
        """启动后台 poll 线程。"""
        if self._poll_thread and self._poll_thread.is_alive():
            return
        self._stop.clear()
        self._poll_thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._poll_thread.start()

    def _poll_loop(self) -> None:
        while not self._stop.is_set():
            self._p.poll(0.1)  # 触发 delivery 回调
        self._p.poll(0)  # 最后一次，把剩余回调放出

    def _on_delivery(self, err, msg) -> None:
        with self._lock:
            if err:
                self.failed += 1
                self.last_error = str(err)
                metrics.PRODUCED.inc(1, result="error")
                log.error("投递失败: %s", err)
            else:
                self.delivered += 1
                metrics.PRODUCED.inc(1, result="ok")

    def produce(self, key: str, value: bytes, topic: str | None = None) -> None:
        """投递一条消息。

        **刻意不传 callback=**（课 12 坑 #6）：
          confluent-kafka 的 produce() 签名是 (topic, value, key, on_delivery=...)。
          若业务代码写 callback= 会被吞进 **kwargs 静默失效 —— 测试会假绿。
        """
        self._p.produce(
            topic or config.TOPIC_ORDERS,
            value,
            key=key,
            on_delivery=self._on_delivery,
        )

    def flush(self, timeout: float = 10.0) -> int:
        """等待在途消息完成。返回未完成的条数（0 = 全部成功）。"""
        return self._p.flush(timeout)

    def close(self) -> None:
        self._stop.set()
        if self._poll_thread:
            self._poll_thread.join(timeout=5)
        try:
            self.flush(5)
        except Exception as e:  # noqa: BLE001
            log.warning("close 时 flush 异常: %s", e)


# ---------- 3. lag 采集（课 12 + 本课补测）----------


def collect_lag(consumer: Consumer, topic: str, timeout: float = 3.0) -> dict[int, float]:
    """计算每分区 lag = watermark_hi - committed。

    **为什么不用 stats 里的 consumer_lag**（课 12 主结论）：
      - 它只对「最近一个统计周期内收到过 fetch 响应」的分区赋值
      - 分区停拉就回退 -1
      - rebalance 后被剥夺分区从 assignment 消失，导致合计骤降（本课补测：5000→2440）

    **为什么用 committed 而不是 position**（本课补测）：
      rebalance 后 position() 返回 -1001 哨兵值，committed 才是可信的。

    返回 {partition: lag}。取不到 watermark 的分区**不出现在结果里**
    （而不是塞 -1）—— 避免 -1 参与 sum 导致低估，这是课 12 坑 #2。
    """
    out: dict[int, float] = {}
    for tp in consumer.assignment():
        if tp.topic != topic:
            continue
        try:
            lo, hi = consumer.get_watermark_offsets(tp, timeout=timeout)
            if hi < 0:
                continue
            cm = consumer.committed([tp], timeout=timeout)[0].offset
            # committed 可能是 -1001（无位移）或 None
            offset = cm if (cm is not None and cm >= 0) else 0
            out[tp.partition] = max(0.0, float(hi - offset))
        except Exception as e:  # noqa: BLE001
            log.debug("分区 %s lag 采集异常: %s", tp.partition, e)
    return out


def group_lag_total(consumer: Consumer, topic: str) -> float:
    """本实例可见分区的 lag 合计。

    ⚠️ 课 13 核心警示：**这不是全组的 lag**。
    rebalance 后本实例只看到自己的分区，合计会凭空缩水。
    生产监控必须每个实例上报自己的分区，再由 Prometheus 按 group 聚合：
        sum(capstone_consumer_lag) by (group)
    """
    return float(sum(collect_lag(consumer, topic).values()))


# ---------- 4. 消费者构造 ----------


def build_consumer(stats_cb=None) -> Consumer:
    conf = config.consumer_conf()
    if stats_cb:
        conf["stats_cb"] = stats_cb
    return Consumer(conf)
