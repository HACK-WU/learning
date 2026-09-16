# -*- coding: utf-8 -*-
"""Evals 层：轨迹评估——确定性匹配 + LLM 裁判。

运行（离线部分）：uv run pytest tests_l13/test_evals.py -v
运行（含 LLM 裁判）：uv run pytest tests_l13/test_evals.py -m integration -v

轨迹素材来源：本课「非确定性」实验的真实运行结构
（问题 E：5 次运行出现 4 种工具路径，其中一次未完成退货意图）。
"""
import os

import pytest
from langchain.messages import AIMessage, HumanMessage, ToolMessage

from agentevals.trajectory.match import create_trajectory_match_evaluator


def _msg(role, content='', tool_calls=None, tool_call_id=None):
    """便捷构造消息（None 字段不传入，避免校验问题）。"""
    if role == 'human':
        return HumanMessage(content=content)
    if role == 'ai':
        kwargs = {'content': content}
        if tool_calls:
            kwargs['tool_calls'] = tool_calls
        return AIMessage(**kwargs)
    return ToolMessage(content=content, tool_call_id=tool_call_id)


def _call(name, args, cid):
    return {'id': cid, 'name': name, 'args': args}


# 参考轨迹（「期望的正确行为」）：查订单 → 发起退货 → 告知结果
REFERENCE = [
    _msg('human', '这个订单 A12345 我不想要了，帮我处理一下'),
    _msg('ai', tool_calls=[_call('query_order', {'order_id': 'A12345'}, 'c1')]),
    _msg('tool', '订单 A12345：已发货，承运商=顺丰，运单号=SF10086。', tool_call_id='c1'),
    _msg('ai', tool_calls=[_call('apply_return', {'order_id': 'A12345'}, 'c2')]),
    _msg('tool', '已为订单 A12345 发起退货申请，退货单号=R20240916，请等待审核。', tool_call_id='c2'),
    _msg('ai', '已为您发起退货申请，退货单号 R20240916，请等待审核。'),
]


# ---------------------------------------------------------------- e1
def test_strict_match_ignores_wording():
    """strict 模式：结构一致即通过，措辞不同不影响。"""
    evaluator = create_trajectory_match_evaluator(trajectory_match_mode='strict')
    outputs = [
        _msg('human', '这个订单 A12345 我不想要了，帮我处理一下'),
        _msg('ai', tool_calls=[_call('query_order', {'order_id': 'A12345'}, 'x1')]),
        _msg('tool', '订单 A12345：已发货，承运商=顺丰，运单号=SF10086。', tool_call_id='x1'),
        _msg('ai', tool_calls=[_call('apply_return', {'order_id': 'A12345'}, 'x2')]),
        _msg('tool', '已为订单 A12345 发起退货申请，退货单号=R20240916，请等待审核。', tool_call_id='x2'),
        _msg('ai', '亲，已经帮您提交退货啦，单号 R20240916～'),  # 措辞不同——不影响 strict 判定
    ]
    result = evaluator(outputs=outputs, reference_outputs=REFERENCE)
    assert result['score'] is True


# ---------------------------------------------------------------- e2
def test_superset_catches_missing_action():
    """superset 模式：实测中「没办成事」的那次运行会被抓出来。

    问题 E 的第 2 次运行（实跑记录）：只查了物流、没发起退货——
    用户要求「帮我处理（退货）」，这类缺关键动作的轨迹必须判失败。
    """
    evaluator = create_trajectory_match_evaluator(trajectory_match_mode='superset')
    missed = [  # 实跑轨迹：#2 只查询了订单与物流，未调用 apply_return
        _msg('human', '这个订单 A12345 我不想要了，帮我处理一下'),
        _msg('ai', tool_calls=[_call('query_order', {'order_id': 'A12345'}, 'm1')]),
        _msg('tool', '订单 A12345：已发货，承运商=顺丰，运单号=SF10086。', tool_call_id='m1'),
        _msg('ai', tool_calls=[_call('query_logistics', {'order_id': 'A12345'}, 'm2')]),
        _msg('tool', '订单 A12345 物流：昨天 14:00 到达【杭州转运中心】，正在派送中。', tool_call_id='m2'),
        _msg('ai', '订单已发货，正派送中。给您两个选择：直接拒收……'),
    ]
    result = evaluator(outputs=missed, reference_outputs=REFERENCE)
    assert result['score'] is False  # 缺 apply_return → 判失败，回归被抓到


# ---------------------------------------------------------------- e3
def test_strict_vs_unordered_on_swapped_order():
    """顺序语义：工具调用顺序调换时，strict 失败而 unordered 通过。"""
    strict = create_trajectory_match_evaluator(trajectory_match_mode='strict')
    unordered = create_trajectory_match_evaluator(trajectory_match_mode='unordered')

    reference = [
        _msg('human', '帮我查订单'),
        _msg('ai', tool_calls=[_call('query_order', {'order_id': 'A1'}, 'r1')]),
        _msg('tool', '订单 A1 状态', tool_call_id='r1'),
        _msg('ai', tool_calls=[_call('query_logistics', {'order_id': 'A1'}, 'r2')]),
        _msg('tool', '订单 A1 物流', tool_call_id='r2'),
        _msg('ai', '查询完成'),
    ]
    swapped = [  # 物流与订单的查询顺序对调
        _msg('human', '帮我查订单'),
        _msg('ai', tool_calls=[_call('query_logistics', {'order_id': 'A1'}, 's1')]),
        _msg('tool', '订单 A1 物流', tool_call_id='s1'),
        _msg('ai', tool_calls=[_call('query_order', {'order_id': 'A1'}, 's2')]),
        _msg('tool', '订单 A1 状态', tool_call_id='s2'),
        _msg('ai', '查询完成'),
    ]

    assert strict(outputs=swapped, reference_outputs=reference)['score'] is False
    assert unordered(outputs=swapped, reference_outputs=reference)['score'] is True


# ---------------------------------------------------------------- e4
@pytest.mark.integration
def test_llm_judge_without_reference(require_api_key):
    """LLM 裁判：无需参考轨迹，裁判模型给整体质量打分（本机用百炼模型作裁判）。"""
    from langchain.chat_models import init_chat_model
    from agentevals.trajectory.llm import (
        create_trajectory_llm_as_judge,
        TRAJECTORY_ACCURACY_PROMPT,
    )

    judge_model = init_chat_model(
        'qwen3.8-flash',
        model_provider='openai',
        base_url=os.environ['BAILIAN_BASE_URL'],
        api_key=os.environ['BAILIAN_API_KEY'],
    )
    evaluator = create_trajectory_llm_as_judge(
        judge=judge_model,
        prompt=TRAJECTORY_ACCURACY_PROMPT,
    )
    result = evaluator(outputs=REFERENCE)
    assert result['score'] is True
    assert isinstance(result['comment'], str) and len(result['comment']) > 0
