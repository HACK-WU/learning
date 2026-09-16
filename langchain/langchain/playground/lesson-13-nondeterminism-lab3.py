# -*- coding: utf-8 -*-
"""课 13 实验 1c：高模糊场景路径分岔——退货意图 + 4 工具。"""
import os
import time
from collections import Counter
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

@tool
def apply_return(order_id: str) -> str:
    """为指定订单发起退货申请。"""
    return f'已为订单 {order_id} 发起退货申请，退货单号=R20240916，请等待审核。'

@tool
def query_refund(order_id: str) -> str:
    """查询指定订单的退款进度。"""
    return f'订单 {order_id} 暂无退款记录。'

model = init_chat_model(
    'qwen3.8-flash', model_provider='openai',
    base_url=os.environ['BAILIAN_BASE_URL'],
    api_key=os.environ['BAILIAN_API_KEY'],
)
agent = create_agent(
    model,
    tools=[query_order, query_logistics, apply_return, query_refund],
    system_prompt='你是电商客服小助手，帮助用户查询订单、物流，处理退货与退款。回答简洁友好。',
)

def run_once(question, n):
    t0 = time.time()
    r = agent.invoke({'messages': [{'role': 'user', 'content': question}]})
    dt = time.time() - t0
    tool_calls = []
    for m in r['messages']:
        for tc in (getattr(m, 'tool_calls', None) or []):
            tool_calls.append(tc['name'])
    return {'run': n, 'seq': '->'.join(tool_calls) if tool_calls else '(无)', 'secs': round(dt, 1),
            'reply': r['messages'][-1].content.replace('\n', ' ')[:60]}

print('=' * 72)
print('问题 E（高模糊）：这个订单 A12345 我不想要了，帮我处理一下')
print('=' * 72)
seqs = []
for i in range(1, 6):
    row = run_once('这个订单 A12345 我不想要了，帮我处理一下', i)
    seqs.append(row['seq'])
    print(f"  #{row['run']} | 工具链={row['seq']} | 耗时={row['secs']}s")
    print(f"       | 回复={row['reply']}")
print()
print('工具链分布:', dict(Counter(seqs)))
print('路径种类数:', len(set(seqs)), '/ 5 次')
