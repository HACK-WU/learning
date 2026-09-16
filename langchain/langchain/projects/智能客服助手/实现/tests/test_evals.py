# -*- coding: utf-8 -*-
"""Evals 层（课 13）：轨迹评估——检查「该做的动作有没有做」。

运行：uv run pytest tests/test_evals.py -v（离线，不需要密钥）
"""
from langchain.messages import AIMessage, HumanMessage, ToolMessage

from agentevals.trajectory.match import create_trajectory_match_evaluator


def _msg(role, content="", tool_calls=None, tool_call_id=None):
    if role == "human":
        return HumanMessage(content=content)
    if role == "ai":
        kwargs = {"content": content}
        if tool_calls:
            kwargs["tool_calls"] = tool_calls
        return AIMessage(**kwargs)
    return ToolMessage(content=content, tool_call_id=tool_call_id)


def _call(name, args, cid):
    return {"id": cid, "name": name, "args": args}


# 参考轨迹（期望的正确流程）：确认订单 → 发起退款 → 告知结果
REFERENCE = [
    _msg("human", "订单 A1001 有质量问题，我要退款"),
    _msg("ai", tool_calls=[_call("process_refund", {"order_id": "A1001", "amount": 399.0}, "c1")]),
    _msg("tool", "已为订单 A1001 发起退款 ￥399.00（原路退回），预计 1-3 个工作日到账。", tool_call_id="c1"),
    _msg("ai", "已为您发起退款，预计 1-3 个工作日到账。"),
]


def test_full_refund_flow_passes_superset():
    """完整退款轨迹（含必需动作）应通过 superset 检查。"""
    evaluator = create_trajectory_match_evaluator(trajectory_match_mode="superset")
    result = evaluator(outputs=REFERENCE, reference_outputs=REFERENCE)
    assert result["score"] is True


def test_missing_refund_action_is_caught():
    """「只查了订单、没发起退款」的轨迹必须被判失败（回归网的核心价值）。"""
    evaluator = create_trajectory_match_evaluator(trajectory_match_mode="superset")
    missed = [
        _msg("human", "订单 A1001 有质量问题，我要退款"),
        _msg("ai", tool_calls=[_call("query_order", {"order_id": "A1001"}, "m1")]),
        _msg("tool", "订单 A1001：星云智能音箱 Pro｜已签收", tool_call_id="m1"),
        _msg("ai", "您的订单已签收，请放心，我们会跟进处理。"),  # 没办退款
    ]
    result = evaluator(outputs=missed, reference_outputs=REFERENCE)
    assert result["score"] is False


def test_extra_safe_actions_allowed_superset():
    """多做无害动作（先查订单再退款）仍应通过 superset（允许超集）。"""
    evaluator = create_trajectory_match_evaluator(trajectory_match_mode="superset")
    extra = [
        _msg("human", "订单 A1001 有质量问题，我要退款"),
        _msg("ai", tool_calls=[_call("query_order", {"order_id": "A1001"}, "x0")]),
        _msg("tool", "订单 A1001：星云智能音箱 Pro｜已签收", tool_call_id="x0"),
        _msg("ai", tool_calls=[_call("process_refund", {"order_id": "A1001", "amount": 399.0}, "x1")]),
        _msg("tool", "已为订单 A1001 发起退款 ￥399.00（原路退回）", tool_call_id="x1"),
        _msg("ai", "已为您发起退款。"),
    ]
    result = evaluator(outputs=extra, reference_outputs=REFERENCE)
    assert result["score"] is True
