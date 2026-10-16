"""退款工单的测试套件。

知识点回指（本文件是阶段 4 · 课 12 的直接落地）：
- 课 12「单元与集成测试」——假服务消除随机性、不接网络
- 课 12 实测教训：假模型不能塞 State，要走 config["configurable"]

分三层：
1. 单节点测试（不跑整图，最快）
2. 整图集成测试（跑完整流程）
3. 韧性测试（重试 / 幂等 / 恢复）
"""
from __future__ import annotations

import pytest
from langgraph.checkpoint.memory import InMemorySaver

from refund_agent import RefundService
from refund_agent.clients import (
    FakeRefundClient,
    FakeRiskClient,
    FakeRiskClientWrongError,
)
from refund_agent.deps import Deps
from refund_agent.nodes.flow import decide, validate
from refund_agent.state import empty_state

# ---------------------------------------------------------------------------
# 第 1 层：单节点
# ---------------------------------------------------------------------------
def test_validate_rejects_empty_order_id():
    """订单号为空 → 直接拒绝，不调风控。"""
    s = empty_state("", 100.0)
    out = validate(s)
    assert out["decision"] == "拒绝"


def test_validate_rejects_non_positive_amount():
    s = empty_state("ORD-1", 0)
    out = validate(s)
    assert out["decision"] == "拒绝"


def test_validate_passes_valid_order():
    s = empty_state("ORD-1", 100.0)
    out = validate(s)
    assert "校验通过" in out["log"][0]


@pytest.mark.parametrize(
    "risk,amount,expected",
    [
        (0.2, 100.0, "通过"),    # 低风险小额 → 自动通过
        (0.6, 100.0, "待人工"),  # 中风险 → 人工
        (0.3, 2000.0, "待人工"), # 低风险但大额 → 人工（金额条件独立生效）
        (0.9, 100.0, "拒绝"),    # 高风险 → 自动拒绝
    ],
)
def test_decide_matrix(risk, amount, expected):
    """判定矩阵：风险与金额两个维度独立生效。"""
    s = empty_state("ORD-1", amount)
    s["risk"] = risk
    assert decide(s)["decision"] == expected


# ---------------------------------------------------------------------------
# 第 2 层：整图集成
# ---------------------------------------------------------------------------
def test_small_amount_auto_approved():
    """小额低风险全自动走完。"""
    svc = RefundService(deps=Deps.fake(risk_score=0.3))
    r = svc.submit("ORD-1", 200.0)
    assert r["decision"] == "通过"
    assert r["refund_id"] == "RF-ORD-1-200.0"


def test_high_risk_auto_rejected():
    """高风险自动拒绝，且不产生退款。"""
    svc = RefundService(deps=Deps.fake(risk_score=0.9))
    r = svc.submit("ORD-2", 200.0)
    assert r["decision"] == "拒绝"
    assert r["refund_id"] == ""


def test_log_is_accumulated_not_overwritten():
    """log 是累加的——验证 Annotated[list, add] 生效（课 3 的坑）。"""
    svc = RefundService(deps=Deps.fake(risk_score=0.3))
    r = svc.submit("ORD-3", 200.0)
    # 全流程 5 个节点各写一条
    assert len(r["log"]) == 5, f"log 被覆盖了？实际 {len(r['log'])} 条: {r['log']}"


# ---------------------------------------------------------------------------
# 第 3 层：韧性
# ---------------------------------------------------------------------------
def test_retry_works_for_transient_error():
    """抛 TransientUpstreamError → 重试生效（风控被调 3 次后成功）。"""
    deps = Deps.fake()
    deps.risk = FakeRiskClient(fail_times=2, score_value=0.3)
    svc = RefundService(deps=deps)

    r = svc.submit("ORD-A", 200.0)
    assert r["decision"] == "通过"
    assert deps.risk.calls == 3, "应当重试到成功"


def test_retry_does_not_work_for_value_error():
    """反例：抖动却抛 ValueError → 配了 retry 也不重试（课 10 实测）。"""
    deps = Deps.fake()
    deps.risk = FakeRiskClientWrongError(fail_times=1, score_value=0.3)
    svc = RefundService(deps=deps)

    with pytest.raises(ValueError):
        svc.submit("ORD-B", 200.0)
    assert deps.risk.calls == 1, "ValueError 不该被重试"


def test_refund_is_idempotent_under_retry():
    """退款重试多次，但幂等键相同 → 只产生一个退款单。"""
    deps = Deps.fake()
    deps.refund = FakeRefundClient(fail_times=1)
    svc = RefundService(deps=deps)

    r = svc.submit("ORD-C", 300.0)
    assert len(deps.refund.calls) == 2        # 调了 2 次
    assert len(set(deps.refund.calls)) == 1   # 但幂等键只有 1 个
    assert r["refund_id"] == "RF-ORD-C-300.0"


def test_interrupt_requires_checkpointer_to_resume():
    """没 checkpointer：能停但 get_state 报错（课 8 实测）。"""
    svc = RefundService(deps=Deps.fake(risk_score=0.3))  # 无 checkpointer
    r = svc.submit("ORD-D", 2000.0)
    assert r["decision"] == "待人工"

    with pytest.raises(ValueError, match="No checkpointer set"):
        svc.get_state("refund-ORD-D")


def test_human_approval_resume():
    """有 checkpointer：能停能恢复，人工批准后续跑。"""
    svc = RefundService(deps=Deps.fake(risk_score=0.3), checkpointer=InMemorySaver())
    svc.submit("ORD-E", 2000.0)

    st = svc.get_state("refund-ORD-E")
    assert st.next == ("human_approve",)

    r = svc.approve("refund-ORD-E", True)
    assert r["decision"] == "通过"
    assert r["refund_id"] == "RF-ORD-E-2000.0"


def test_thread_isolation():
    """不同 thread 互不干扰（课 5 thread_id 隔离）。"""
    svc = RefundService(deps=Deps.fake(risk_score=0.3), checkpointer=InMemorySaver())
    r1 = svc.submit("ORD-F", 200.0, thread_id="t1")
    r2 = svc.submit("ORD-G", 200.0, thread_id="t2")
    assert r1["order_id"] == "ORD-F"
    assert r2["order_id"] == "ORD-G"
    assert r1["log"] != r2["log"]
