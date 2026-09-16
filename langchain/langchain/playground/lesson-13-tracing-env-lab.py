# -*- coding: utf-8 -*-
"""课 13 实验：LangSmith tracing 环境变量行为（无 key 场景）。

运行：uv run python lesson-13-tracing-env-lab.py 2>&1

本脚本回答三个问题：
1. 开启 tracing 但没有 key 时，运行会发生什么？
2. 警告与上报失败日志长什么样？
3. 运行中途修改 tracing 环境变量有效吗？（本机实测：无效，详见末尾说明）
"""
import os
import warnings
from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool

# ---- 在程序启动阶段就把 tracing 环境变量配置好 --------------------------------
os.environ['LANGSMITH_TRACING'] = 'true'
os.environ.pop('LANGSMITH_API_KEY', None)  # 故意不配置 key，观察表现


@tool
def get_weather(city: str) -> str:
    """查询城市天气。"""
    return f'{city}：晴，22°C。'


def build_agent():
    model = init_chat_model(
        'qwen3.8-flash', model_provider='openai',
        base_url=os.environ['BAILIAN_BASE_URL'],
        api_key=os.environ['BAILIAN_API_KEY'],
    )
    return create_agent(model, tools=[get_weather], system_prompt='用工具查询天气。')


print('=' * 72)
print('1. 首次运行：警告 + 后台尝试上报（观察 stderr 的 401 日志）')
print('=' * 72)
print(f'LANGSMITH_TRACING = {os.environ.get("LANGSMITH_TRACING")}')
print(f'LANGSMITH_API_KEY = {"已设置" if os.environ.get("LANGSMITH_API_KEY") else "未设置"}')

agent = build_agent()
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter('always')
    r = agent.invoke({'messages': [{'role': 'user', 'content': '北京天气？'}]})

print(f'>>> agent 正常运行，回复: {r["messages"][-1].content[:48]}')
for w in caught:
    print(f'[警告] {type(w.message).__name__}: {str(w.message)[:80]}')
print('（另有后台上报失败日志打在 stderr：Authentication failed ... 401）')

print()
print('=' * 72)
print('2. 再次运行：不再重复警告（Python warnings 去重），功能照常')
print('=' * 72)
with warnings.catch_warnings(record=True) as caught:
    warnings.simplefilter('always')
    r2 = agent.invoke({'messages': [{'role': 'user', 'content': '上海天气？'}]})
print(f'>>> 正常运行，回复: {r2["messages"][-1].content[:48]}')
print(f'此轮新警告数: {len([w for w in caught if "LangSmith" in type(w.message).__name__])}')

print()
print('=' * 72)
print('3. tracing_context：按调用粒度开关追踪')
print('=' * 72)
import langsmith as ls

with ls.tracing_context(enabled=False):
    r3 = agent.invoke({'messages': [{'role': 'user', 'content': '广州天气？'}]})
print(f'>>> enabled=False 调用正常: {r3["messages"][-1].content[:48]}')

with ls.tracing_context(project_name='my-agent-tests', enabled=True):
    r4 = agent.invoke({'messages': [{'role': 'user', 'content': '深圳天气？'}]})
print(f'>>> 指定 project_name 调用正常: {r4["messages"][-1].content[:48]}')
print('（无 key 时不会真正上报，但代码路径与有 key 时一致）')

print()
print('=' * 72)
print('附：本机实测的「固化」行为（重要，请留意）')
print('=' * 72)
print('tracing 的启用状态在进程内首次调用时确定并固化：')
print('  · 首次调用时已开启（如本脚本）→ 生效（警告 + 上报尝试可见）')
print('  · 首次调用时未开启，之后再设置 LANGSMITH_TRACING → 本进程内不生效')
print('    （本机对照实测：stderr 零上报日志，即连尝试都不会发生）')
print('建议：LANGSMITH_* 环境变量在程序启动前配置好；中途修改请重启进程。')
