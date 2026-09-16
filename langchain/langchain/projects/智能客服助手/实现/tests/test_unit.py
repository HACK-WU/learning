# -*- coding: utf-8 -*-
"""单元测试层（课 13）：用剧本模型 + 内存存储测 agent 组装逻辑（零 API 调用、秒级、确定）。

运行：uv run pytest tests/test_unit.py -v
"""
from langchain.messages import AIMessage, HumanMessage, ToolCall
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel

from app.agent import build_agent
from app.middleware.safety import phone_detector
from app.tools.aftersales import ACTIONS, process_refund


class ScriptedToolModel(GenericFakeChatModel):
    """剧本模型 + 工具支持（内置 fake 模型未实现 bind_tools——课 13 实测补充）。"""

    def bind_tools(self, tools, *, tool_choice=None, **kwargs):
        return self


def _refund_call(order_id: str, amount: float) -> AIMessage:
    return AIMessage(
        content="",
        tool_calls=[ToolCall(name="process_refund", args={"order_id": order_id, "amount": amount}, id="call-1")],
    )


# ---------------------------------------------------------------- u1
def test_phone_detector_matches_cn_mobile():
    """手机号 detector：命中中国大陆手机号、不误伤其他数字串。"""
    hit = phone_detector("联系我：13812345678 或 19900001111")
    assert [m["value"] for m in hit] == ["13812345678", "19900001111"]

    miss = phone_detector("订单号 A1001，金额 399 元，日期 2026-09-12")
    assert miss == []


# ---------------------------------------------------------------- u2
def test_small_refund_passes_without_approval(clean_ledgers):
    """小额退款（< 阈值）：when 谓词为 False → 直通执行、不中断。"""
    model = ScriptedToolModel(
        messages=iter([_refund_call("A1004", 29.0), "已为您退款，预计 1-3 个工作日到账。"])
    )
    agent = build_agent(model=model)

    result = agent.invoke(
        {"messages": [HumanMessage(content="订单 A1004 的贴膜用不上，退了吧。")]},
        {"configurable": {"thread_id": "u2"}},
    )

    assert "__interrupt__" not in result                      # 未触发审批
    assert any(a["type"] == "refund" and a["order_id"] == "A1004" for a in ACTIONS)  # 工具真的执行了
    assert result["messages"][-1].content


# ---------------------------------------------------------------- u3
def test_large_refund_requires_approval(clean_ledgers):
    """大额退款（>= 阈值）：中断等待审批 → approve 后才执行。"""
    model = ScriptedToolModel(
        messages=iter([_refund_call("A1001", 399.0), "退款已处理，原路退回 1-3 个工作日到账。"])
    )
    agent = build_agent(model=model)
    cfg = {"configurable": {"thread_id": "u3"}}

    # 第一次调用：应中断（工具被冻结、未执行）
    result = agent.invoke(
        {"messages": [HumanMessage(content="订单 A1001 的智能音箱有质量问题，我要退款。")]},
        cfg,
    )
    assert "__interrupt__" in result
    request = result["__interrupt__"][0].value
    assert request["action_requests"][0]["args"]["amount"] == 399.0
    assert not any(a["type"] == "refund" for a in ACTIONS)     # 未执行

    # 人工批准 → resume：工具执行、流程收尾
    from langgraph.types import Command

    result2 = agent.invoke(
        Command(resume={"decisions": [{"type": "approve"}]}), cfg
    )
    assert any(a["type"] == "refund" and a["order_id"] == "A1001" for a in ACTIONS)
    assert result2["messages"][-1].content


# ---------------------------------------------------------------- u4
def test_refund_amount_mismatch_rejected(clean_ledgers):
    """防幻觉护栏：退款金额与订单实付不一致时拒绝执行（工具内部校验）。"""
    result = process_refund.invoke({"order_id": "A1001", "amount": 100.0})
    assert "校验不通过" in result
    assert not any(a["type"] == "refund" for a in ACTIONS)
