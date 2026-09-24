"""课 13 —— 指标层：手写 Prometheus 文本暴露格式（课 12 落地）。

为什么不用 prometheus-client：
  1. l11 镜像未装，装包属改环境（按规矩需用户点头）
  2. **手撕一遍文本格式，才知道 scrape 到底发生了什么** —— 这正是本课要讲的
  3. 文本格式协议很简单，<150 行就能覆盖需求

Prometheus 文本格式最小规范（v0.0.4）：
    # HELP <name> <描述>          # 描述里反斜杠和换行要转义
    # TYPE <name> <counter|gauge|histogram|summary>
    <name>{<label>="<v>",...} <value> [timestamp_ms]

对应课程：课 12（可观测与测试）、课 3（JMX 指标语义三步核验）。
"""

from __future__ import annotations

import threading
import time
from typing import Iterable

# ---------- 指标原语 ----------


class Counter:
    """单调递增计数器。只增不减，重启归零（Prometheus 端用 rate() 处理）。"""

    def __init__(self, name: str, help_text: str, labels: Iterable[str] = ()):
        self.name = name
        self.help_text = help_text
        self.labels = tuple(labels)
        self._lock = threading.Lock()
        self._values: dict[tuple, float] = {}

    def inc(self, amount: float = 1.0, **labels) -> None:
        key = self._key(labels)
        with self._lock:
            self._values[key] = self._values.get(key, 0.0) + amount

    def _key(self, labels: dict) -> tuple:
        miss = set(self.labels) - set(labels)
        if miss:
            raise ValueError(f"{self.name}: 缺 label {miss}")
        return tuple(labels[k] for k in self.labels)

    def collect(self) -> list[tuple[tuple, float]]:
        with self._lock:
            return list(self._values.items())


class Gauge:
    """可升可降的瞬时值。**lag 就是 Gauge，不是 Counter**（课 12 实测：5000→2440）。"""

    def __init__(self, name: str, help_text: str, labels: Iterable[str] = ()):
        self.name = name
        self.help_text = help_text
        self.labels = tuple(labels)
        self._lock = threading.Lock()
        self._values: dict[tuple, float] = {}

    def set(self, value: float, **labels) -> None:
        with self._lock:
            self._values[self._key(labels)] = value

    def _key(self, labels: dict) -> tuple:
        miss = set(self.labels) - set(labels)
        if miss:
            raise ValueError(f"{self.name}: 缺 label {miss}")
        return tuple(labels[k] for k in self.labels)

    def collect(self) -> list[tuple[tuple, float]]:
        with self._lock:
            return list(self._values.items())


# ---------- 注册表 ----------


class Registry:
    """极简注册表。线程安全，够用即可。"""

    def __init__(self):
        self._lock = threading.Lock()
        self._metrics: list[Counter | Gauge] = []

    def register(self, m: Counter | Gauge) -> Counter | Gauge:
        with self._lock:
            self._metrics.append(m)
        return m

    def render(self, extra: dict[str, tuple[str, str, dict[tuple, float]]] | None = None) -> str:
        """渲染为 Prometheus 文本格式。

        extra: 动态指标（如 lag，分区数运行时才知道），
               格式 {name: (type, help, {(label_values): value})}
        """
        lines: list[str] = []
        for m in self._metrics:
            mtype = "counter" if isinstance(m, Counter) else "gauge"
            lines.append(f"# HELP {m.name} {_escape(m.help_text)}")
            lines.append(f"# TYPE {m.name} {mtype}")
            for key, val in m.collect():
                lines.append(f"{m.name}{_fmt_labels(m.labels, key)} {_fmt_num(val)}")
        for name, (mtype, help_text, values) in (extra or {}).items():
            labels = ("partition",) if values and len(next(iter(values))) == 1 else ("topic", "partition")
            lines.append(f"# HELP {name} {_escape(help_text)}")
            lines.append(f"# TYPE {name} {mtype}")
            for key, val in values.items():
                lines.append(f"{name}{_fmt_labels(labels, key)} {_fmt_num(val)}")
        return "\n".join(lines) + "\n"


def _escape(s: str) -> str:
    """HELP/TYPE 文本里，反斜杠和换行必须转义（否则整段 scrape 失败）。"""
    return s.replace("\\", "\\\\").replace("\n", "\\n")


def _fmt_labels(names: Iterable[str], values: Iterable) -> str:
    pairs = [(n, v) for n, v in zip(names, values)]
    if not pairs:
        return ""
    inner = ",".join(f'{n}="{str(v).replace(chr(34), chr(92)+chr(34))}"' for n, v in pairs)
    return "{" + inner + "}"


def _fmt_num(v: float) -> str:
    if v == int(v):
        return str(int(v))
    return repr(float(v))


# ---------- 全局注册表与本课指标 ----------

REGISTRY = Registry()

# 生产侧
PRODUCED = REGISTRY.register(
    Counter("capstone_orders_produced_total", "成功投递到 Kafka 的订单数", ["result"])
)
PRODUCE_LATENCY_BUCKET = REGISTRY.register(
    Counter("capstone_produce_callback_seconds_bucket", "投递确认延迟直方图桶", ["le"])
)

# 消费侧
CONSUMED = REGISTRY.register(
    Counter("capstone_orders_consumed_total", "消费结果计数", ["result"])
)
# result 取值：ok / validation_error / processing_error / dlq

# 健康
CONSUMER_LAG = Gauge(
    "capstone_consumer_lag", "每分区积压量（watermark - committed）", ["topic", "partition"]
)


def render_metrics(lag_values: dict[tuple, float] | None = None) -> str:
    """暴露给 /metrics 用。lag 作为动态指标传入。"""
    extra = {}
    if lag_values is not None:
        extra["capstone_consumer_lag"] = (
            "gauge",
            "每分区积压量（watermark - committed）；-1 表示该分区本轮未取到",
            lag_values,
        )
    return REGISTRY.render(extra)
