"""依赖注入容器。

知识点回指：
- 阶段 4 · 课 12「单元与集成测试」——模型/外部服务不能写死在节点里，要可替换
- 阶段 4 · 课 12 实测教训：把依赖塞进 State 会 KeyError，必须走 config["configurable"]

课 12 实测结论回顾：
    初稿把假模型写进 State 传参，实跑 KeyError: 'model'。
    正解是走 config["configurable"] 注入，节点签名写成 (state, config)。
"""
from __future__ import annotations

from dataclasses import dataclass

from .clients import (
    FakeNotifier,
    FakeRefundClient,
    FakeRiskClient,
    Notifier,
    RefundClient,
    RiskClient,
)

CONFIG_KEY = "deps"  # config["configurable"]["deps"]


@dataclass
class Deps:
    """一次运行所需的全部外部依赖。

    为什么打包成一个对象而不是散着传：
    - 节点签名只需一个 config，加依赖不用改所有节点
    - 测试里替换一处即可
    """
    risk: RiskClient
    refund: RefundClient
    notifier: Notifier

    @staticmethod
    def fake(
        risk_fail_times: int = 0,
        risk_score: float = 0.3,
        refund_fail_times: int = 0,
    ) -> "Deps":
        """默认的假实现——测试与示例用它。"""
        return Deps(
            risk=FakeRiskClient(fail_times=risk_fail_times, score_value=risk_score),
            refund=FakeRefundClient(fail_times=refund_fail_times),
            notifier=FakeNotifier(),
        )


def get_deps(config: dict | None) -> Deps:
    """从 config 里取依赖；没配就给一套假实现（方便单节点调试）。

    知识点回指：阶段 4 · 课 12 —— 节点签名 (state, config)
    """
    if not config:
        return Deps.fake()
    configurable = config.get("configurable") or {}
    deps = configurable.get(CONFIG_KEY)
    if deps is None:
        return Deps.fake()
    return deps
