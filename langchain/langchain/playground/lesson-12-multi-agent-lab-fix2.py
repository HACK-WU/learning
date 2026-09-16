# -*- coding: utf-8 -*-
"""课 12 补跑 B2：有状态 skills 双轮（修正首轮设计缺陷——无 checkpointer 会话不累积）。"""
import os

from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool
from langchain_core.callbacks import BaseCallbackHandler
from langgraph.checkpoint.memory import InMemorySaver

model = init_chat_model(
    "qwen3.8-flash", model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
)


class CountHandler(BaseCallbackHandler):
    def __init__(self):
        self.calls = 0

    def on_chat_model_start(self, serialized, messages, **kwargs):
        self.calls += 1


@tool
def get_weather(city: str) -> str:
    """查询指定城市的当前天气。"""
    return f"{city}：晴，22°C，湿度 40%，东南风 2 级"


@tool
def load_weather_skill() -> str:
    """加载天气流程技能。任务涉及天气查询时必须先加载此技能。"""
    return ('[weather 技能已加载]\n天气查询流程：1) 确认城市；2) 调用 get_weather 工具；'
            '3) 用一句话播报结果（含温度）。')


skill_agent = create_agent(
    model, tools=[load_weather_skill, get_weather],
    system_prompt='你是助手。执行天气任务前必须先调用 load_weather_skill 加载流程技能，'
                  '再按技能指引完成。如果技能已在对话中加载过，则直接执行（不要重复加载）。',
    checkpointer=InMemorySaver(),
)

cfg = {'configurable': {'thread_id': 'fix-b2-thread'}}

c1 = CountHandler()
r1 = skill_agent.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                        {**cfg, 'callbacks': [c1]})
n1 = len(r1['messages'])
print(f"turn1 模型调用: {c1.calls} 次", flush=True)
print("turn1 工具轨迹：", flush=True)
for m in r1['messages']:
    if getattr(m, 'tool_calls', None):
        for tc in m.tool_calls:
            print(f"  -> {tc['name']}", flush=True)
print(flush=True)

c2 = CountHandler()
r2 = skill_agent.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                        {**cfg, 'callbacks': [c2]})
print(f"turn2 模型调用: {c2.calls} 次", flush=True)
print("turn2 新增消息（%d 条起）：" % n1, flush=True)
for m in r2['messages'][n1:]:
    t = getattr(m, 'type', '?')
    if t == 'ai' and getattr(m, 'tool_calls', None):
        for tc in m.tool_calls:
            print(f"  [ai] -> tool: {tc['name']}", flush=True)
    elif t == 'tool':
        s = " ".join(str(m.content).split())[:70]
        print(f"  [tool]: {s}", flush=True)
    elif t == 'ai':
        s = " ".join(str(m.content).split())[:110]
        print(f"  [ai]: {s}", flush=True)
    else:
        s = " ".join(str(m.content).split())[:60]
        print(f"  [{t}]: {s}", flush=True)

print()
print(f"对照注：turn1={c1.calls} 次 / turn2={c2.calls} 次", flush=True)
