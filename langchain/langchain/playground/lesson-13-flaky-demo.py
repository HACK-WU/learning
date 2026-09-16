# -*- coding: utf-8 -*-
"""课 13 实验：为什么断言「内容」必然失败，而断言「结构」稳定通过。

运行：uv run python lesson-13-flaky-demo.py

场景：同一问题跑 3 次——模拟「按第一次的输出给后续运行写断言」的真实做法。
"""
import os
from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool


@tool
def get_weather(city: str) -> str:
    """查询城市天气。"""
    return f'{city}：晴，22°C。'


model = init_chat_model(
    'qwen3.8-flash', model_provider='openai',
    base_url=os.environ['BAILIAN_BASE_URL'],
    api_key=os.environ['BAILIAN_API_KEY'],
)
agent = create_agent(model, tools=[get_weather], system_prompt='用工具查询天气。')


def run_once(n):
    r = agent.invoke({'messages': [{'role': 'user', 'content': '北京天气怎么样？'}]})
    msgs = r['messages']
    reply = msgs[-1].content
    tool_calls = [tc['name'] for m in msgs for tc in (getattr(m, 'tool_calls', None) or [])]
    return reply, tool_calls


print('=' * 72)
print('跑 3 次，记录回复与工具调用')
print('=' * 72)
runs = []
for i in range(1, 4):
    reply, tools = run_once(i)
    runs.append((reply, tools))
    print(f'  #{i} 工具={tools} 回复({len(reply)}字)={reply[:70]}')

print()
print('=' * 72)
print('断言 A（脆弱）：回复 == 第一次运行的原话（快照断言）')
print('=' * 72)
snapshot = runs[0][0]
passed_a = sum(1 for reply, _ in runs if reply == snapshot)
print(f'  期望文本: "{snapshot[:50]}..."')
print(f'  通过次数: {passed_a}/3')
print(f'  → {"稳定" if passed_a == 3 else "不稳定（换一台机器/换一天跑，结果还会变）"}')

print()
print('=' * 72)
print('断言 B（结构）：工具调用含 get_weather 且末条回复非空')
print('=' * 72)
passed_b = sum(1 for reply, tools in runs if 'get_weather' in tools and len(reply) > 0)
print(f'  断言条件: "get_weather" in tool_calls and len(reply) > 0')
print(f'  通过次数: {passed_b}/3')
print(f'  → {"稳定" if passed_b == 3 else "不稳定"}')

print()
print('结论：内容每次不同（断言 A 不可靠），但「行为结构」是稳定的——')
print('     集成测试断言结构；更严格的质量评估交给 evals（数据集 + 评判器）。')
