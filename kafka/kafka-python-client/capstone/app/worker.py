"""课 13 —— 消费者 worker（课 6 手动提交 + 课 10 并发模型 + 课 12 可观测）。

本模块承载本课的 4 个核心能力：
  1. **手动提交**：业务处理成功后才 commit，崩溃不丢消息（课 6）
  2. **坏消息进 DLQ**：校验失败的重试一万次也不会成功，直接隔离（课 9 契约 + 课 12 错误处理）
  3. **优雅退出**：收到信号 -> 停止拉新 -> 处理完在手的 -> 提交 -> 退出（本课新能力）
  4. **rebalance 感知**：分区被剥夺时正确清理状态（本课补测结论）

设计取舍：**单线程处理 + 手动提交**，而不是线程池并发。
  理由（课 10 结论）：多线程消费必须处理"位移乱序提交"问题——
  线程 A 处理完 offset=100，线程 B 还在处理 offset=50，此时提交 100 会让 50 变成"已处理"。
  正确做法是按分区加锁或按分区单线程。本课选**逐分区串行**，最简单也最不容易错。
"""

from __future__ import annotations

import json
import logging
import os
import signal
import threading
import time
from dataclasses import dataclass, field

from confluent_kafka import Consumer, Producer, TopicPartition

from . import config, metrics
from .kafka_client import collect_lag
from .schema import OrderEvent, ValidationError

log = logging.getLogger("capstone.worker")


@dataclass
class WorkerStats:
    ok: int = 0
    validation_error: int = 0
    processing_error: int = 0
    dlq: int = 0
    committed: int = 0
    rebalances: int = 0
    partitions_revoked: int = 0
    last_lag: dict = field(default_factory=dict)


class OrderWorker:
    """订单消费 worker。

    生命周期：start() -> run loop -> stop()（优雅退出）
    """

    def __init__(self, consumer: Consumer | None = None, producer=None, process_fn=None):
        self._c = consumer or self._default_consumer()
        self._p = producer
        self._process_fn = process_fn or default_process
        self._running = threading.Event()
        self._thread: threading.Thread | None = None
        self.stats = WorkerStats()
        self._lock = threading.Lock()
        self._lag: dict[tuple[str, int], float] = {}
        self._assigned: set = set()
        self._closing = False
        self._pending_commits = 0
        # lag 后台采集：默认 30 秒一次（单次约 1.5s，占消费时间 5%）
        self._lag_interval = float(os.getenv("LAG_REFRESH_INTERVAL", "30.0"))
        self._lag_stop = threading.Event()
        self._lag_thread: threading.Thread | None = None

    # ---------- 构造 ----------

    def _default_consumer(self) -> Consumer:
        from .kafka_client import build_consumer

        return build_consumer(stats_cb=self._on_stats)

    def _on_stats(self, stats_json: str) -> None:
        """课 12：从 stats 回调里抓 rebalance 次数，用于可观测。"""
        try:
            s = json.loads(stats_json)
            cg = s.get("cgrp", {})
            rc = cg.get("rebalance_cnt", 0)
            if rc and rc > self.stats.rebalances:
                with self._lock:
                    self.stats.rebalances = rc
        except Exception:  # noqa: BLE001 - stats 回调异常绝不能影响消费
            pass

    # ---------- 生命周期 ----------

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._running.set()
        self._lag_stop.clear()
        self._lag_thread = threading.Thread(target=self._lag_loop, daemon=True,
                                            name="lag-collector")
        self._lag_thread.start()
        self._thread = threading.Thread(target=self._run, daemon=True, name="order-worker")
        self._thread.start()
        log.info("worker 已启动（lag 采集间隔 %.0fs，独立线程）", self._lag_interval)

    def stop(self, timeout: float = 30.0) -> bool:
        """优雅退出（本课核心能力 #3）。

        顺序很重要：
          1. 置 _closing，让循环不再拉新消息
          2. 等待当前批次处理完
          3. 提交已处理的位移（**这一步不能省**，省了就重复消费）
          4. close()

        返回 True 表示在 timeout 内干净退出。
        """
        log.info("收到停止信号，开始优雅退出…")
        self._closing = True
        self._running.clear()
        self._lag_stop.set()
        if self._lag_thread:
            self._lag_thread.join(timeout=5)
        if self._thread:
            self._thread.join(timeout=timeout)
            clean = not self._thread.is_alive()
        else:
            clean = True
        try:
            # 退出前最后提交一次：把已处理但未提交的位移落盘
            self._c.commit(asynchronous=False)
            log.info("退出前最终提交完成（committed=%d）", self.stats.committed)
        except Exception as e:  # noqa: BLE001
            # 没有位移可提交时会抛 _NO_OFFSET，属正常（课 12 见过）
            log.warning("退出前提交跳过: %s", type(e).__name__)
        try:
            self._c.close()
        except Exception as e:  # noqa: BLE001
            log.warning("close 异常: %s", e)
        log.info("worker 已退出（clean=%s）", clean)
        return clean

    # ---------- 主循环 ----------

    def _run(self) -> None:
        self._c.subscribe(
            [config.TOPIC_ORDERS],
            on_assign=self._on_assign,
            on_revoke=self._on_revoke,
        )
        log.info("已订阅 %s", config.TOPIC_ORDERS)

        # 设计说明（**注意：这里曾有过一次误诊，保留教训**）：
        #
        #   初版在消费循环里每条消息后调 _refresh_lag()，实测吞吐个位数/s，
        #   当时判定"lag 采集压热路径"并做了节流修复。后经对照实验证明
        #   **诊断是错的**——真凶是测试脚本与运行中的服务共用 group.id，
        #   触发持续 rebalance；停掉同组其他成员后裸循环达 237688 条/秒。
        #
        #   但以下两点仍是**正确的工程实践**（与性能无关，是为解耦与语义）：
        #     1. lag 采集（单次约 1.5s，get_watermark_offsets 主导）交给独立
        #        后台线程 _lag_loop，不占消费线程 —— 避免任何 IO 抖动传导到消费
        #     2. 提交用 asynchronous=True + 退出前同步兜底 —— 见 _commit 注释
        #
        # 因此本循环只做：poll -> 处理 -> 异步登记提交。不碰任何网络查询。
        while self._running.is_set():
            msg = self._c.poll(timeout=1.0)
            if msg is None:
                continue
            if msg.error():
                log.error("消费错误: %s", msg.error())
                metrics.CONSUMED.inc(1, result="error")
                continue
            self._handle(msg)

    def _refresh_lag(self) -> None:
        """刷新 lag 快照。

        ⚠️ 单次耗时约 1.5 秒（get_watermark_offsets 主导），
        **只能由独立后台线程低频调用**，绝不能进消费循环。
        """
        try:
            lag = collect_lag(self._c, config.TOPIC_ORDERS)
            with self._lock:
                self._lag = {(config.TOPIC_ORDERS, p): v for p, v in lag.items()}
                self.stats.last_lag = dict(lag)
        except Exception:  # noqa: BLE001
            pass

    def _lag_loop(self) -> None:
        """独立的 lag 采集线程（课 13 性能修复的核心）。

        为什么要独立线程：lag 采集是 1.5 秒级的重操作，
        放消费线程里会直接吃掉吞吐（实测占 30%+）。
        独立后消费线程完全不受影响，代价是指标有 <=N 秒延迟——
        对 lag 这种"趋势型"指标完全可接受。
        """
        while not self._lag_stop.is_set():
            try:
                self._refresh_lag()
            except Exception:  # noqa: BLE001
                pass
            self._lag_stop.wait(self._lag_interval)

    def _on_assign(self, consumer, partitions) -> None:
        self._assigned = {tp.partition for tp in partitions}
        log.info("分配到分区: %s", sorted(self._assigned))

    def _on_revoke(self, consumer, partitions) -> None:
        """**分区被剥夺** —— 本课补测的核心场景。

        正确做法：在 revoke 回调里同步提交已处理位移。
        如果不提交，新 owner 会从旧位移重复消费（at-least-once 的直接代价）。
        """
        log.warning("分区被剥夺: %s", sorted(tp.partition for tp in partitions))
        with self._lock:
            self.stats.partitions_revoked += len(partitions)
        try:
            consumer.commit(asynchronous=False)
            log.info("revoke 前已同步提交位移")
        except Exception as e:  # noqa: BLE001
            log.warning("revoke 提交失败: %s", type(e).__name__)

    # ---------- 消息处理 ----------

    def _handle(self, msg) -> None:
        raw = msg.value()
        try:
            order = OrderEvent.from_json(raw)
        except ValidationError as e:
            # 坏消息：重试无意义 -> DLQ
            self._to_dlq(raw, str(e))
            with self._lock:
                self.stats.validation_error += 1
            metrics.CONSUMED.inc(1, result="validation_error")
            self._commit(msg)
            return

        try:
            self._process_fn(order)
        except Exception as e:  # noqa: BLE001
            log.exception("处理 order_id=%s 失败", order.order_id)
            with self._lock:
                self.stats.processing_error += 1
            metrics.CONSUMED.inc(1, result="processing_error")
            # 处理失败：不提交位移 -> 会被重新消费（at-least-once）
            # 生产里应配合重试次数上限 + DLQ，见 README
            return

        with self._lock:
            self.stats.ok += 1
        metrics.CONSUMED.inc(1, result="ok")
        self._commit(msg)

    def _commit(self, msg) -> None:
        """提交位移 —— 异步登记，退出时同步兜底。

        语义（课 6）：**处理成功后才提交**，因此不会丢消息。
        异步提交不阻塞消费线程；`stop()` 里会做一次同步提交兜底，
        保证退出前位移落盘。

        ⚠️ 诚实说明：初版用 asynchronous=False，后被我改异步并声称
        "实测同步提交让吞吐掉 710 倍"。**那个对照实验结论不可信**——
        实验中多个消费者共用 group.id 触发持续 rebalance，污染了数据。
        干净复测（独立 group、无同组竞争）下裸循环 237688 条/秒，
        同步提交的影响远没有 710 倍那么夸张。

        异步提交**仍然保留**，但理由是解耦（提交不阻塞消费线程），
        不是"修复性能"。请勿再引用那个被污染的数字。
        """
        try:
            self._c.commit(message=msg, asynchronous=True)
            self._pending_commits += 1
            with self._lock:
                self.stats.committed += 1
        except Exception as e:  # noqa: BLE001
            log.error("提交位移失败: %s", e)

    def _to_dlq(self, raw: bytes, reason: str) -> None:
        """发送到死信队列。"""
        if self._p is None:
            log.warning("无生产者，DLQ 跳过: %s", reason)
            return
        payload = json.dumps(
            {"reason": reason, "raw": raw.decode("utf-8", errors="replace"),
             "ts": time.time()},
            ensure_ascii=False,
        ).encode()
        try:
            self._p.produce(config.TOPIC_DLQ, payload)
            self._p.poll(0)  # 触发回调（课 6：不 poll 回调不执行）
            with self._lock:
                self.stats.dlq += 1
            metrics.CONSUMED.inc(1, result="dlq")
        except Exception as e:  # noqa: BLE001
            log.error("写入 DLQ 失败: %s", e)

    # ---------- 对外查询 ----------

    def lag_snapshot(self) -> dict[tuple[str, int], float]:
        with self._lock:
            return dict(self._lag)

    def lag_total(self) -> float:
        return float(sum(self.lag_snapshot().values()))

    def is_healthy(self) -> tuple[bool, str]:
        """健康检查（课 12）：worker 在跑 + 有分区分配。

        注意：不把 lag 大小作为健康判据 —— lag 高是"忙"不是"病"，
        用 lag 做健康判据会导致扩容时所有实例被误杀（课 12 教训）。
        """
        alive = self._thread is not None and self._thread.is_alive()
        if not alive:
            return False, "worker 线程未运行"
        if self._closing:
            return False, "正在优雅退出"
        if not self._assigned:
            return False, "未分配到分区（可能在 rebalance）"
        return True, "ok"


# ---------- 默认业务处理 ----------


def default_process(order: OrderEvent) -> None:
    """默认业务逻辑：只做校验级的"处理"。

    真实业务会写库/调外部服务。这里刻意保持无副作用，
    让分层测试（课 12）可以稳定断言。
    """
    if order.amount <= 0:  # 契约已挡，兜底
        raise ValueError("amount 非法")
    return None


def install_signal_handlers(worker: OrderWorker) -> None:
    """注册 SIGTERM/SIGINT -> 优雅退出。

    **这是"敢上生产"的关键一环**：容器 stop 时先发 SIGTERM，
    若程序不处理，10s 后被 SIGKILL —— 在途消息和未提交位移全丢。
    """

    def handler(signum, frame):
        log.info("收到信号 %s，触发优雅退出", signum)
        worker.stop()

    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            signal.signal(sig, handler)
        except ValueError:
            pass  # 非主线程注册会失败，忽略
