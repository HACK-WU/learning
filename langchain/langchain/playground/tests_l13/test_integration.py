# -*- coding: utf-8 -*-
"""集成测试层：真实调用模型 API（默认排除；用 -m integration 显式运行）。

运行：uv run pytest tests_l13/test_integration.py -m integration -v

注意：这一层的断言对象是「结构」而非「内容」——模型每次措辞都不同，
断言具体文本必然失败（见 lesson-13-flaky-demo.py 的实测对照）。
"""
import os

import pytest
from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, HumanMessage
from langchain.tools import tool


@tool
def get_weather(city: str) -> str:
    """查询城市天气。"""
    return f'{city}：晴，22°C。'


@pytest.fixture
def model(require_api_key):
    return init_chat_model(
        'qwen3.8-flash',
        model_provider='openai',
        base_url=os.environ['BAILIAN_BASE_URL'],
        api_key=os.environ['BAILIAN_API_KEY'],
    )


@pytest.mark.integration
def test_agent_calls_weather_tool(model):
    """结构断言：不猜内容，只查结构（工具被调用、结尾是 AI 消息、非空）。"""
    agent = create_agent(model, tools=[get_weather])
    result = agent.invoke({'messages': [HumanMessage(content='北京天气怎么样？')]})
    messages = result['messages']

    tool_calls = [
        tc
        for msg in messages
        if hasattr(msg, 'tool_calls')
        for tc in (msg.tool_calls or [])
    ]

    assert any(tc['name'] == 'get_weather' for tc in tool_calls)
    assert isinstance(messages[-1], AIMessage)
    assert len(messages[-1].content) > 0


@pytest.mark.integration
def test_agent_responds_without_tool(require_api_key):
    """无工具场景：验证「不调工具也能正常回答」这条最小路径。"""
    model = init_chat_model(
        'qwen3.8-flash',
        model_provider='openai',
        base_url=os.environ['BAILIAN_BASE_URL'],
        api_key=os.environ['BAILIAN_API_KEY'],
    )
    agent = create_agent(model, tools=[])
    result = agent.invoke({'messages': [HumanMessage(content='用一句话打个招呼')]})

    assert isinstance(result['messages'][-1], AIMessage)
    assert len(result['messages'][-1].content) > 0
