"""分层测试 L1：纯逻辑层，不碰 Kafka（课 12 分层测试落地）。

这一层用标准库 unittest（**不引入 pytest**，零新增依赖）。
跑一次 <0.1 秒，可以在写代码时反复跑。

课 12 教训（坑 #6）：fake 必须与真实 API **同宽容度**。
  confluent 的 produce() 签名是 (topic, value, key, on_delivery=...)，
  如果 fake 只认 on_delivery 而业务代码传 callback=，真实库会静默吞掉
  （进 **kwargs 不报错）-> 回调永不执行 -> 测试假绿。
  下面的 StrictFake 就是照着真实签名写的。
"""

from __future__ import annotations

import json
import threading
import unittest

from app.schema import (
    OrderEvent, ValidationError, validate_order, MAX_AMOUNT,
)
from app.worker import OrderWorker, default_process
from app import metrics


# ---------- Fake 层：与真实 confluent API 同签名 ----------


class FakeProducer:
    """照 confluent_kafka.Producer 的真实签名写。

    真实签名：produce(topic, value, key=None, on_delivery=None, **kwargs)
    **kwargs 会被静默接受 —— 这个宽容度必须保留，否则测不出"参数名写错"的 bug。
    """

    def __init__(self):
        self.sent: list[tuple[str, bytes, str | None]] = []
        self.poll_count = 0
        self._callbacks: list = []

    def produce(self, topic, value, key=None, on_delivery=None, **kwargs):
        # 关键：不校验 kwargs 里的未知参数，与真实库一致
        self.sent.append((topic, value, key))
        if on_delivery is not None:
            self._callbacks.append((on_delivery, topic, value, key))

    def poll(self, timeout=0):
        """真实语义：poll 触发待处理的 delivery 回调。"""
        self.poll_count += 1
        if self._callbacks:
            for cb, topic, value, key in self._callbacks:
                cb(None, FakeMessage(topic, value, key))
            self._callbacks.clear()
        return 0

    def flush(self, timeout=0):
        self.poll(0)
        return 0


class FakeMessage:
    def __init__(self, topic, value, key=None, partition=0, offset=0):
        self._topic, self._value, self._key = topic, value, key
        self._partition, self._offset = partition, offset

    def topic(self): return self._topic
    def value(self): return self._value
    def key(self): return self._key
    def partition(self): return self._partition
    def offset(self): return self._offset
    def error(self): return None


class FakeConsumer:
    """最小可用 fake：够 L1 测 worker 逻辑。"""

    def __init__(self, messages=None):
        self._messages = list(messages or [])
        self.committed: list = []
        self.closed = False
        self.assignment_result = []
        self.subscribe_calls = []

    def subscribe(self, topics, on_assign=None, on_revoke=None):
        self.subscribe_calls.append(topics)
        self._on_assign, self._on_revoke = on_assign, on_revoke

    def poll(self, timeout=0):
        if not self._messages:
            return None
        return self._messages.pop(0)

    def commit(self, message=None, asynchronous=True):
        self.committed.append(message)
        return None

    def close(self): self.closed = True
    def assignment(self): return self.assignment_result


# ---------- 测试用例 ----------


class TestSchema(unittest.TestCase):
    """课 9：契约校验。"""

    def test_valid_order_roundtrip(self):
        ev = OrderEvent("o1", "u1", 99.5, "CNY")
        raw = ev.to_json()
        back = OrderEvent.from_json(raw)
        self.assertEqual(back.order_id, "o1")
        self.assertEqual(back.amount, 99.5)

    def test_missing_field_rejected(self):
        with self.assertRaises(ValidationError) as ctx:
            validate_order({"order_id": "o1"})
        self.assertIn("缺字段", str(ctx.exception))

    def test_negative_amount_rejected(self):
        with self.assertRaises(ValidationError):
            validate_order({"order_id": "o1", "user_id": "u", "amount": -1, "currency": "CNY"})

    def test_bool_is_not_valid_amount(self):
        """Python 陷阱：bool 是 int 的子类，True == 1。"""
        with self.assertRaises(ValidationError) as ctx:
            validate_order({"order_id": "o", "user_id": "u", "amount": True, "currency": "CNY"})
        self.assertIn("须为数字", str(ctx.exception))

    def test_invalid_currency(self):
        with self.assertRaises(ValidationError) as ctx:
            validate_order({"order_id": "o", "user_id": "u", "amount": 1, "currency": "JPY"})
        self.assertIn("currency 非法", str(ctx.exception))

    def test_over_max_amount(self):
        with self.assertRaises(ValidationError):
            validate_order({"order_id": "o", "user_id": "u",
                            "amount": MAX_AMOUNT + 1, "currency": "CNY"})

    def test_malformed_json(self):
        with self.assertRaises(ValidationError):
            OrderEvent.from_json(b"{not json")


class TestWorkerWithFake(unittest.TestCase):
    """worker 逻辑层测试 —— 不碰 Kafka。"""

    def setUp(self):
        self.prod = FakeProducer()
        self.good = OrderEvent("o1", "u1", 10.0, "CNY").to_json()
        self.bad = json.dumps({"order_id": "bad", "user_id": "u",
                               "amount": -5, "currency": "CNY"}).encode()

    def test_good_message_committed(self):
        c = FakeConsumer([FakeMessage("t", self.good)])
        w = OrderWorker(consumer=c, producer=self.prod)
        w._handle(FakeMessage("t", self.good))
        self.assertEqual(w.stats.ok, 1)
        self.assertEqual(len(c.committed), 1)  # 处理后必须提交

    def test_bad_message_goes_to_dlq_and_still_commits(self):
        """坏消息：进 DLQ + **仍然提交**。

        为什么坏消息也要提交？它重试一万次也不会成功，
        不提交会导致消费者卡在这条消息上（毒丸消息）。
        """
        c = FakeConsumer([])
        w = OrderWorker(consumer=c, producer=self.prod)
        w._handle(FakeMessage("t", self.bad))
        self.assertEqual(w.stats.validation_error, 1)
        self.assertEqual(w.stats.dlq, 1)
        self.assertEqual(len(self.prod.sent), 1)
        self.assertIn("dlq", self.prod.sent[0][0].lower())
        self.assertEqual(len(c.committed), 1)

    def test_processing_error_does_not_commit(self):
        """处理失败：**不提交** -> 会被重新消费（at-least-once）。"""
        def boom(order): raise RuntimeError("下游挂了")
        c = FakeConsumer([])
        w = OrderWorker(consumer=c, producer=self.prod, process_fn=boom)
        w._handle(FakeMessage("t", self.good))
        self.assertEqual(w.stats.processing_error, 1)
        self.assertEqual(len(c.committed), 0)  # 关键：没提交

    def test_dlq_requires_poll_to_deliver(self):
        """课 6：produce 后必须 poll，否则回调不执行。

        worker 的 _to_dlq 里显式调了 poll(0)，这里断言它确实调了。
        """
        c = FakeConsumer([])
        w = OrderWorker(consumer=c, producer=self.prod)
        before = self.prod.poll_count
        w._handle(FakeMessage("t", self.bad))
        self.assertGreater(self.prod.poll_count, before)

    def test_health_reports_no_partition(self):
        """线程在跑但没分到分区 -> 不健康（rebalance 中）。

        注意：必须让 _thread **真的存活**，否则会先命中"线程未运行"分支，
        测不到本用例想覆盖的"rebalance 期间不健康"这一层。
        """
        c = FakeConsumer([])
        w = OrderWorker(consumer=c, producer=self.prod)
        gate = threading.Event()
        w._thread = threading.Thread(target=gate.wait, daemon=True)
        w._thread.start()
        try:
            self.assertTrue(w._thread.is_alive())
            ok, reason = w.is_healthy()
            self.assertFalse(ok)
            self.assertIn("分区", reason)
        finally:
            gate.set()


class TestMetricsRendering(unittest.TestCase):
    """课 12：Prometheus 文本格式必须能被真解析。"""

    def test_render_has_help_and_type(self):
        metrics.PRODUCED.inc(1, result="ok")
        out = metrics.render_metrics({("capstone-orders", 0): 42.0})
        self.assertIn("# HELP capstone_orders_produced_total", out)
        self.assertIn("# TYPE capstone_orders_produced_total counter", out)
        self.assertIn('capstone_orders_produced_total{result="ok"} 1', out)

    def test_lag_is_gauge_not_counter(self):
        """课 12 主结论：lag 是 gauge（可升可降）。"""
        out = metrics.render_metrics({("capstone-orders", 0): 5000.0})
        self.assertIn("# TYPE capstone_consumer_lag gauge", out)
        self.assertIn("capstone_consumer_lag{", out)

    def test_help_text_escaping(self):
        """HELP 里有反斜杠必须转义，否则整段 scrape 失败。"""
        g = metrics.Gauge("test_esc", "路径 C:\\tmp 与 换行\n")
        r = metrics.Registry(); r.register(g)
        g.set(1.0)
        out = r.render()
        self.assertIn("C:\\\\tmp", out)
        self.assertNotIn("\n# TYPE", out.split("# HELP")[1].split("# TYPE")[0])

    def test_missing_label_raises(self):
        with self.assertRaises(ValueError):
            metrics.PRODUCED.inc(1)  # 缺 result


if __name__ == "__main__":
    unittest.main(verbosity=2)
