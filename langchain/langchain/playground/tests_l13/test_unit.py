# -*- coding: utf-8 -*-
"""单元测试层：用「剧本模型」+ 内存持久化测 agent 逻辑（零 API 调用、秒级、免费、确定）。

运行：uv run pytest tests_l13/test_unit.py -v
"""
from langchain.agents import create_agent
from langchain.messages import AIMessage, HumanMessage, ToolCall
from langchain.tools import tool
from langchain_core.language_models.fake_chat_models import GenericFakeChatModel
from langgraph.checkpoint.memory import InMemorySaver


class ScriptedToolModel(GenericFakeChatModel):
    """剧本模型 + 工具支持。

    内置 fake 模型（含 GenericFakeChatModel）都未实现 bind_tools，
    直接配合带工具的 create_agent 会抛 NotImplementedError。
    剧本里已经预设了 tool_calls，绑定时原样返回自身即可。
    """

    def bind_tools(self, tools, *, tool_choice=None, **kwargs):
        return self


@tool
def get_weather(city: str) -> str:
    """查询城市天气。"""
    return f'{city}：晴，22°C。'


# ---------------------------------------------------------------- u1
def test_fake_model_returns_scripted_text():
    """最底层：剧本模型按顺序吐出预设回复。"""
    model = GenericFakeChatModel(messages=iter(['你好，我是剧本里的回复。']))
    result = model.invoke('你好')
    assert result.content == '你好，我是剧本里的回复。'


# ---------------------------------------------------------------- u2
def test_agent_with_scripted_text():
    """agent 层（无工具）：剧本只写了文本 → 消息序列应为 用户 → AI 两条。"""
    model = GenericFakeChatModel(messages=iter(['北京今天晴，22 度。']))
    agent = create_agent(model, tools=[])

    result = agent.invoke({'messages': [HumanMessage(content='北京天气？')]})
    messages = result['messages']

    assert len(messages) == 2
    assert isinstance(messages[-1], AIMessage)
    assert messages[-1].content == '北京今天晴，22 度。'


# ---------------------------------------------------------------- u3
def test_agent_executes_tool_from_scripted_call():
    """工具链路：剧本发起工具调用 → agent 执行工具 → 结果回传 → 终答。

    验证的正是「机制」：模型侧的 tool_calls 如何被 agent 执行并回填。
    """
    model = ScriptedToolModel(messages=iter([
        AIMessage(content='', tool_calls=[ToolCall(name='get_weather', args={'city': '北京'}, id='call_1')]),
        '北京今天晴，22 度。',
    ]))
    agent = create_agent(model, tools=[get_weather])

    result = agent.invoke({'messages': [HumanMessage(content='北京天气？')]})
    messages = result['messages']

    # 用户 → AI(含 tool_calls) → 工具结果 → AI(终答)
    assert len(messages) == 4
    assert messages[1].tool_calls[0]['name'] == 'get_weather'
    assert messages[2].type == 'tool'
    assert messages[2].content == '北京：晴，22°C。'
    assert messages[3].content == '北京今天晴，22 度。'


# ---------------------------------------------------------------- u4
def test_multi_turn_memory_with_in_memory_saver():
    """多轮记忆：InMemorySaver 让第二次调用能看到第一轮的消息。"""
    model = GenericFakeChatModel(messages=iter([
        '好的，记住了：你住在悉尼。',
        '你那边现在是 GMT+10。',
    ]))
    agent = create_agent(model, tools=[], checkpointer=InMemorySaver())
    config = {'configurable': {'thread_id': 'session-1'}}

    agent.invoke({'messages': [HumanMessage(content='我住在悉尼。')]}, config=config)
    second = agent.invoke({'messages': [HumanMessage(content='我这边几点了？')]}, config=config)

    # 第二轮返回的消息里包含两轮全部消息（4 条）——第一轮被持久化了
    assert len(second['messages']) == 4
    assert second['messages'][0].content == '我住在悉尼。'
    assert second['messages'][2].content == '我这边几点了？'


# ---------------------------------------------------------------- u5
def test_scripted_agent_is_deterministic():
    """确定性：同一剧本、同一输入，反复运行结果完全一致（对照真实模型 4/4 不同）。"""
    replies = set()
    for _ in range(3):
        model = GenericFakeChatModel(messages=iter(['固定回复']))
        agent = create_agent(model, tools=[])
        result = agent.invoke({'messages': [HumanMessage(content='你好')]})
        replies.add(result['messages'][-1].content)

    assert replies == {'固定回复'}  # 3 次运行收敛为 1 种结果
