# -*- coding: utf-8 -*-
"""课 13 实验 1：非确定性实证——同一输入多次运行，路径与输出差异记录。"""
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
    """跑一次并提取轨迹特征。"""
    t0 = time.time()
    r = agent.invoke({'messages': [{'role': 'user', 'content': question}]})
    dt = time.time() - t0
    msgs = r['messages']
    # 提取工具调用序列
    tool_calls = []
    for m in msgs:
        for tc in (getattr(m, 'tool_calls', None) or []):
            tool_calls.append(f"{tc['name']}({tc['args'].get('order_id', '?')})")
    final = msgs[-1].content
    return {
        'run': n,
        'messages': len(msgs),
        'tool_seq': ' -> '.join(tool_calls) if tool_calls else '(无工具调用)',
        'reply_len': len(final),
        'reply': final.replace('\n', ' ')[:66],
        'secs': round(dt, 1),
    }

print('=' * 72)
print('问题 A（信息完整）：帮我查一下订单 A12345 的物流，谢谢')
print('=' * 72)
rows_a = []
for i in range(1, 5):
    row = run_once('帮我查一下订单 A12345 的物流，谢谢', i)
    rows_a.append(row)
    print(f"  #{row['run']} | 消息数={row['messages']} | 工具链={row['tool_seq']}")
    print(f"       | 回复({row['reply_len']}字)={row['reply']}")
    print(f"       | 耗时={row['secs']}s")

print()
print('=' * 72)
print('问题 B（信息不全）：我的包裹怎么还没到啊？')
print('=' * 72)
rows_b = []
for i in range(1, 5):
    row = run_once('我的包裹怎么还没到啊？', i)
    rows_b.append(row)
    print(f"  #{row['run']} | 消息数={row['messages']} | 工具链={row['tool_seq']}")
    print(f"       | 回复({row['reply_len']}字)={row['reply']}")
    print(f"       | 耗时={row['secs']}s")

print()
print('=' * 72)
print('汇总：工具链差异')
print('=' * 72)
print('问题 A 工具链集合:', set(r['tool_seq'] for r in rows_a))
print('问题 B 工具链集合:', set(r['tool_seq'] for r in rows_b))
print('问题 A 回复去重数:', len(set(r['reply'] for r in rows_a)))
print('问题 B 回复去重数:', len(set(r['reply'] for r in rows_b)))
