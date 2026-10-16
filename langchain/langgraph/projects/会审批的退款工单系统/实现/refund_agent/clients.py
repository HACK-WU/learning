"""外部服务（风控 / 退款 / 通知）的可替换实现。

知识点回指：
- 阶段 4 · 课 12「单元与集成测试」——假模型/假服务要能替换，不能写死在节点里
- 阶段 3 · 课 10「Fault-tolerance」——要能抛出可重试的异常

设计要点：
- 真实实现走网络，测试里换成 Fake 实现（同一个接口）
- FlakyRisk 系列专门用于演示"重试生效 / 不生效"的差别
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# 异常分类：这一层决定了 retry_policy 是否生效
# 知识点回指：阶段 3 · 课 10 —— default_retry_on 挑异常
#
# 实测结论（课 10）：默认 retry_on 对 ValueError/TypeError/RuntimeError/OSError
# 返回 False（认为是代码 bug，不重试）；对 ConnectionError 与自定义异常返回 True。
# 所以"外部接口抖动"必须用可重试的异常类型表达，否则配了 retry 也不重试。
# ---------------------------------------------------------------------------
class TransientUpstreamError(Exception):
    """外部系统临时故障——应该被重试。"""


class PermanentUpstreamError(Exception):
    """外部系统明确拒绝——不该被重试（重试只会浪费时间）。"""


# ---------------------------------------------------------------------------
# 接口定义
# ---------------------------------------------------------------------------
class RiskClient:
    """风控接口。"""

    def score(self, order_id: str, amount: float) -> float:
        raise NotImplementedError


class RefundClient:
    """退款接口（有副作用，必须幂等）。"""

    def refund(self, order_id: str, amount: float, idempotency_key: str) -> str:
        raise NotImplementedError


class Notifier:
    """通知接口。"""

    def notify(self, order_id: str, message: str) -> None:
        raise NotImplementedError


# ---------------------------------------------------------------------------
# 真实实现（示意：生产里这里会打日志、上报指标、走连接池）
# ---------------------------------------------------------------------------
@dataclass
class HttpRiskClient(RiskClient):
    endpoint: str = "https://risk.example.com/score"

    def score(self, order_id: str, amount: float) -> float:
        # 真实实现：requests.post(self.endpoint, ...)
        raise NotImplementedError("本教程不接真实网络，测试请用 FakeRiskClient")


# ---------------------------------------------------------------------------
# 测试替身
# ---------------------------------------------------------------------------
@dataclass
class FakeRiskClient(RiskClient):
    """可控的风控假实现。

    fail_times: 前 N 次抛 TransientUpstreamError（模拟抖动）
    """
    fail_times: int = 0
    score_value: float = 0.3
    calls: int = field(default=0, init=False)

    def score(self, order_id: str, amount: float) -> float:
        self.calls += 1
        if self.calls <= self.fail_times:
            raise TransientUpstreamError(
                f"风控接口抖动（第 {self.calls}/{self.fail_times} 次）"
            )
        return self.score_value


@dataclass
class FakeRiskClientWrongError(RiskClient):
    """反面教材：抖动却抛 ValueError —— 配了 retry 也不会重试。

    知识点回指：阶段 3 · 课 10 实测，ValueError 被 default_retry_on 判为 False。
    """
    fail_times: int = 0
    score_value: float = 0.3
    calls: int = field(default=0, init=False)

    def score(self, order_id: str, amount: float) -> float:
        self.calls += 1
        if self.calls <= self.fail_times:
            # ⚠️ 错误的异常类型：这是"看起来配了重试、实际不重试"的第一大坑
            raise ValueError(f"风控接口抖动（第 {self.calls} 次）")
        return self.score_value


@dataclass
class FakeRefundClient(RefundClient):
    """退款假实现，带幂等键记录——用来验证"重试没打两次款"。

   知识点回指：阶段 3 · 课 10 —— 重试必须配合幂等，否则重复扣款
    """
    fail_times: int = 0
    calls: list = field(default_factory=list, init=False)

    def refund(self, order_id: str, amount: float, idempotency_key: str) -> str:
        self.calls.append(idempotency_key)
        if len(self.calls) <= self.fail_times:
            raise TransientUpstreamError(f"退款接口抖动（第 {len(self.calls)} 次）")
        # 幂等：同一个 key 只产生一个退款单号
        return f"RF-{idempotency_key}"


@dataclass
class FakeNotifier(Notifier):
    messages: list = field(default_factory=list, init=False)

    def notify(self, order_id: str, message: str) -> None:
        self.messages.append((order_id, message))


@dataclass
class RandomRiskClient(RiskClient):
    """随机失败的风控（用于压测 / 演示"随机性怎么测"）。

    知识点回指：阶段 4 · 课 12 —— 随机性必须可复现（固定 seed）
    """
    fail_rate: float = 0.5
    seed: int = 42
    rng: random.Random = field(init=False)

    def __post_init__(self):
        self.rng = random.Random(self.seed)

    def score(self, order_id: str, amount: float) -> float:
        if self.rng.random() < self.fail_rate:
            raise TransientUpstreamError("风控随机抖动")
        return 0.3
