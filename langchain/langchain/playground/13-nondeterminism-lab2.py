# -*- coding: utf-8 -*-
"""课 13 实验 1b：路径分岔补测——模糊意图下工具选择是否浮动。"""
import os
import time
from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool

@tool
def query_order(order_id: str) -> str:
    """根据订单号查询订单状态。"""
    return f'订单 {order_id}：已发货，承运商=顺丰，运单号=SF10086。'

@tool
def query_logistics(order_id: str) -> str:
    """根据订单号查询物流轨迹。"""
    return f'订单 {order_id} 物流：昨天 14:00 到达【杭州转运中心】，正在派送中。'

model = init_chat_model(
    'qwen3.8-flash', model_provider='openai',
    base_url=os.environ['BAILIAN_BASE_URL'],
    api_key=os.environ['BAILIAN_API_KEY'],
)
agent = create_agent(
    model,
    tools=[query_order, query_logistics],
    system_prompt='你是电商客服小助手，帮助用户查询订单与物流。回答简洁友好。',
)

def run_once(question, n):
    t0 = time.time()
    r = agent.invoke({'messages': [{'role': 'user', 'content': question}]})
    dt = time.time() - t0
    msgs = r['messages']
    tool_calls = []
    for m in msgs:
        for tc in (getattr(m, 'tool_calls', None) or []):
            tool_calls.append(f"{tc['name']}")
    return {
        'run': n,
        'messages': len(msgs),
        'tools': tool_calls,
        'seq': '->'.join(tool_calls) if tool_calls else '(无)',
        'secs': round(dt, 1),
    }

print('=' * 72)
print('问题 C（模糊：订单 A12345 怎么还没到？）——跑 5 次看工具选择分布')
print('=' * 72)
from collections import Counter
seqs = []
for i in range(1, 6):
    row = run_once('订单 A12345 怎么还没到？', i)
    seqs.append(row['seq'])
    print(f"  #{row['run']} | 消息数={row['messages']} | 工具链={row['seq']} | 耗时={row['secs']}s")
print()
print('工具链分布:', dict(Counter(seqs)))

print()
print('=' * 72)
print('问题 D（开放式：帮我看看 A12345 这个订单）——跑 5 次')
print('=' * 72)
seqs2 = []
for i in range(1, 6):
    row = run_once('帮我看看 A12345 这个订单', i)
    seqs2.append(row['seq'])
    print(f"  #{row['run']} | 消息数={row['messages']} | 工具链={row['seq']} | 耗时={row['secs']}s")
print()
print('工具链分布:', dict(Counter(seqs2)))
