# -*- coding: utf-8 -*-
"""录制回放层：首次真实调用写入 cassette 文件，之后离线重放。

运行：uv run pytest tests_l13/test_vcr.py -v

- 首次运行：真实调用模型并把「请求/响应」录到 cassettes/*.yaml（自动脱敏）
- 之后运行：从 cassette 回放，零 API 调用、零成本、结果稳定
- 修改脚本后若与 cassette 对不上：删掉对应 yaml 重新录制
"""
import os

import pytest
from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.messages import HumanMessage
from langchain.tools import tool


@tool
def get_weather(city: str) -> str:
    """查询城市天气。"""
    return f'{city}：晴，22°C。'


def _build_model():
    return init_chat_model(
        'qwen3.8-flash',
        model_provider='openai',
        base_url=os.environ['BAILIAN_BASE_URL'],
        api_key=os.environ['BAILIAN_API_KEY'],
    )


@pytest.mark.vcr()
def test_agent_trajectory_record_and_replay():
    """录制/回放：验证 agent 会调用天气工具并给出非空回答。"""
    agent = create_agent(_build_model(), tools=[get_weather])
    result = agent.invoke({'messages': [HumanMessage(content='北京天气怎么样？')]})
    messages = result['messages']

    tool_calls = [
        tc
        for msg in messages
        if hasattr(msg, 'tool_calls')
        for tc in (msg.tool_calls or [])
    ]
    assert any(tc['name'] == 'get_weather' for tc in tool_calls)
    assert len(messages[-1].content) > 0
