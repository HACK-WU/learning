# -*- coding: utf-8 -*-
"""课 13 实验：RunTree——trace 的数据模型（完全离线，无需网络与密钥）。

运行：uv run python lesson-13-runtree-lab.py

LangSmith 中的每一条 trace 都是一棵 RunTree：
根 run（一次 agent 调用）+ 子 run（每次模型调用 / 工具执行）……
本脚本用一次「真实运行的时序数据」在本地搭建出同构的树结构，
看清「trace 里到底记录了什么」。
"""
import time

from langsmith.run_trees import RunTree

t0 = time.time()

# ---- 根 run：一次 agent 运行 -------------------------------------------------
root = RunTree(
    name='agent_run',
    run_type='chain',
    inputs={'messages': [{'role': 'user', 'content': '北京天气？'}]},
)

# ---- 子 run 1：第一次 LLM 调用（决定调用工具） --------------------------------
llm1 = root.create_child(
    name='ChatOpenAI',
    run_type='llm',
    inputs={'messages': '[user]: 北京天气？'},
)
llm1.end(outputs={'tool_calls': [{'name': 'get_weather', 'args': {'city': '北京'}}]})

# ---- 子 run 2：工具执行 ------------------------------------------------------
tool1 = root.create_child(
    name='get_weather',
    run_type='tool',
    inputs={'city': '北京'},
)
tool1.end(outputs={'output': '北京：晴，22°C。'})

# ---- 子 run 3：第二次 LLM 调用（基于工具结果作答） ----------------------------
llm2 = root.create_child(
    name='ChatOpenAI',
    run_type='llm',
    inputs={'messages': '[user]: 北京天气？ | [tool]: 北京：晴，22°C。'},
)
llm2.end(outputs={'content': '北京今天晴，22 度。'})

# ---- 根 run 收尾 -------------------------------------------------------------
root.end(outputs={'answer': '北京今天晴，22 度。'})

# ======================================================================
# 打印树结构
# ======================================================================
print('=' * 72)
print('一次 agent 运行对应的 RunTree 结构')
print('=' * 72)


def show(run, depth=0):
    indent = '    ' * depth
    if depth == 0:
        print(f'{indent}[根] {run.name} ({run.run_type})')
    else:
        print(f'{indent}├─[子] {run.name} ({run.run_type})')
    if run.inputs:
        print(f'{indent}      输入: {str(run.inputs)[:60]}')
    if run.outputs:
        print(f'{indent}      输出: {str(run.outputs)[:60]}')
    for child in run.child_runs:
        show(child, depth + 1)


show(root)

print()
print('=' * 72)
print('关键字段说明')
print('=' * 72)
print(f'根本次运行的 trace_id: {str(root.trace_id)[:18]}...')
print(f'每个子 run 都继承同一个 trace_id:')
for c in root.child_runs:
    print(f'  - {c.name}: trace_id={str(c.trace_id)[:18]}... | 自己的 id={str(c.id)[:8]}...')
print()
print('时间字段（start_time / end_time）每个 run 各有一份：')
print(f'  根 run:   {root.start_time.strftime("%H:%M:%S.%f")[:-3]} ~ {root.end_time.strftime("%H:%M:%S.%f")[:-3]}')
for c in root.child_runs:
    print(f'  - {c.name}: {c.start_time.strftime("%H:%M:%S.%f")[:-3]} ~ {c.end_time.strftime("%H:%M:%S.%f")[:-3]}')
print()
print(f'运行总耗时示范值: {(time.time() - t0) * 1000:.1f} ms（本脚本构造耗时，非真实推理）')
