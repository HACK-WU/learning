# -*- coding: utf-8 -*-
"""集成测试层（课 13）：真模型真调用，断言「结构」而不是「内容」。

运行：uv run pytest tests/test_integration.py -m integration -v
"""
import pytest
from langchain.messages import HumanMessage

from app.agent import build_agent


def _tool_names(messages) -> list[str]:
    return [tc["name"] for m in messages for tc in (getattr(m, "tool_calls", None) or [])]


@pytest.mark.integration
def test_policy_question_uses_knowledge_base(require_api_key):
    """政策问题：模型应调用 search_policies 检索知识库（而非凭记忆回答）。"""
    agent = build_agent()
    result = agent.invoke(
        {"messages": [HumanMessage(content="请问退货的运费由谁承担？请按你们的最新政策回答。")]},
        {"configurable": {"thread_id": "i1"}},
    )

    assert "search_policies" in _tool_names(result["messages"])
    assert len(result["messages"][-1].content) > 0


@pytest.mark.integration
def test_order_query_tool_is_called(require_api_key):
    """订单查询：模型应调用 query_order（或 query_logistics）核对事实。"""
    agent = build_agent()
    result = agent.invoke(
        {"messages": [HumanMessage(content="帮我查一下订单 A1003 现在什么状态？")]},
        {"configurable": {"thread_id": "i2"}},
    )

    names = _tool_names(result["messages"])
    assert "query_order" in names or "query_logistics" in names
    # 结构断言：回答中提到订单号（不比对具体措辞）
    assert "A1003" in str(result["messages"][-1].content)
