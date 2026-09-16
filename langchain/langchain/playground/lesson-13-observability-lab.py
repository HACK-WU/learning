# -*- coding: utf-8 -*-
"""课 13 实验：可观测性（本地观测篇）——set_debug 与「迷你 trace」收集器。

运行：uv run python lesson-13-observability-lab.py

不需要任何外部平台：这部分展示「不接 LangSmith 时，怎么看见 agent 内部」。
"""
import time
from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

import os
from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool
from langchain_core.callbacks import BaseCallbackHandler


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


# ======================================================================
# 1. set_debug(True)：把执行细节打印到控制台（最轻量的观测手段）
# ======================================================================
print('=' * 72)
print('1. set_debug 输出（实际运行时打印每个环节；此处仅展示摘要）')
print('=' * 72)
from langchain_core.globals import set_debug

agent = build_agent()
set_debug(True)
r = agent.invoke({'messages': [{'role': 'user', 'content': '北京天气？'}]})
set_debug(False)
print(f'>>> 最终回复: {r["messages"][-1].content[:60]}')
print('（set_debug 打印中可见：两次 LLM 调用（3.08s / 1.26s）、工具执行（1ms）、token 用量等）')

# ======================================================================
# 2. 「迷你 trace」：自定义 callback 收集器
#    —— 理解 trace 的本质 = 每一步的「开始 / 结束 / 输入 / 输出 / 时序」
# ======================================================================
print()
print('=' * 72)
print('2. 迷你 trace（自定义 callback 收集一次运行的全部关键步骤）')
print('=' * 72)


class MiniTraceHandler(BaseCallbackHandler):
    """把 agent 运行的关键步骤收集成一条时间线（trace 的原料）。"""

    def __init__(self):
        self.t0 = time.time()
        self.events = []

    def _t(self):
        return f'+{time.time() - self.t0:6.2f}s'

    def on_chat_model_start(self, serialized, messages, **kwargs):
        n = len(messages[0]) if messages else 0
        self.events.append(f'{self._t()}  ▶ LLM 调用（输入 {n} 条消息）')

    def on_llm_end(self, response, **kwargs):
        gen = response.generations[0][0]
        msg = getattr(gen, 'message', None)
        tool_calls = getattr(msg, 'tool_calls', None) if msg else None
        if tool_calls:
            desc = ', '.join(f"{c['name']}({c['args']})" for c in tool_calls)
            self.events.append(f'{self._t()}  ◀ LLM 返回：请求调用工具 → {desc}')
        else:
            text = (gen.text or '').replace('\n', ' ')[:36]
            self.events.append(f'{self._t()}  ◀ LLM 返回文本：{text}...')

    def on_tool_start(self, serialized, input_str, **kwargs):
        name = serialized.get('name', '?')
        self.events.append(f'{self._t()}  ▶ 工具执行 {name}（入参 {input_str}）')

    def on_tool_end(self, output, **kwargs):
        self.events.append(f'{self._t()}  ◀ 工具返回：{str(output)[:48]}')


handler = MiniTraceHandler()
r = agent.invoke(
    {'messages': [{'role': 'user', 'content': '北京天气？'}]},
    config={'callbacks': [handler]},
)
print(f'{"步骤记录（一次完整运行）":-^60}')
for e in handler.events:
    print(e)
print(f'{"-" * 60}')
print(f'>>> 最终回复: {r["messages"][-1].content[:60]}')
print()
print('对比：LangSmith 存的 trace 就是「这套事件 + 更多细节（token、模型参数、错误栈）」。')
print('实验完成。')
