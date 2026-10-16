"""退款工单的节点实现。

每个节点签名统一为 (state, config) —— 依赖从 config 注入（课 12 实测教训）。

知识点回指：
- 阶段 1 · 课 3「节点返回的是增量」——return {"log": [...]} 而不是全量 state
- 阶段 3 · 课 8「Interrupts」——human_approve 用 interrupt() 卡住
- 阶段 3 · 课 10「Fault-tolerance」——异常类型决定是否被重试
- 阶段 2 · 课 6「Store 长期记忆」——用户画像从长期记忆读（本文件只留接入点）
"""
from __future__ import annotations

from typing import Optional

from langchain_core.runnables import RunnableConfig
from langgraph.types import interrupt

from ..clients import PermanentUpstreamError, TransientUpstreamError
from ..deps import get_deps
from ..state import RefundState

# 幂等键：同一笔订单 + 同一金额 → 同一个 key
# 知识点回指：阶段 3 · 课 10 —— 重试必须幂等，否则重复打款
def _idempotency_key(state: RefundState) -> str:
    return f"{state['order_id']}-{state['amount']}"


# ---------------------------------------------------------------------------
# 1. 校验
# ---------------------------------------------------------------------------
def validate(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """校验工单是否合法（金额必须为正、订单号非空）。"""
    order_id = (state.get("order_id") or "").strip()
    amount = state.get("amount") or 0.0

    if not order_id:
        # 明确的参数错误 → 不可重试（重试一万次还是错）
        return {"log": [f"校验失败: 订单号为空"], "decision": "拒绝", "risk": 1.0}
    if amount <= 0:
        return {"log": [f"校验失败: 金额非正({amount})"], "decision": "拒绝", "risk": 1.0}

    return {"log": [f"校验通过: {order_id} 金额{amount}"]}


# ---------------------------------------------------------------------------
# 2. 风控评分（会抖，需要重试）
# ---------------------------------------------------------------------------
def score_risk(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """调风控接口打分。

    注意抛出的异常类型：
    - TransientUpstreamError → 会被 retry_policy 重试（课 10 实测）
    - 如果这里写 raise ValueError → 配了 retry 也不重试（反例）
    """
    deps = get_deps(config)
    score = deps.risk.score(state["order_id"], state["amount"])
    return {"log": [f"风控评分: {score}"], "risk": score}


# ---------------------------------------------------------------------------
# 3. 判定：要不要人审
# ---------------------------------------------------------------------------
AUTO_APPROVE_RISK = 0.5   # 低于此分自动通过
AUTO_REJECT_RISK = 0.8    # 高于此分自动拒绝

def decide(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """按风险分决定去向：自动通过 / 自动拒绝 / 转人工。

    知识点回指：阶段 1 · 课 2「workflow 与 agent 的分界」
    —— 这里是 workflow：判定规则是写死的 if，不是让 LLM 自己想。
    """
    risk = state.get("risk", 0.0)
    amount = state.get("amount", 0.0)

    # 高风险或大额一律转人工（双条件，任一命中即人工）
    if risk >= AUTO_REJECT_RISK:
        return {"log": [f"判定: 风险{risk}≥{AUTO_REJECT_RISK} 自动拒绝"], "decision": "拒绝"}
    if risk >= AUTO_APPROVE_RISK or amount >= 1000:
        return {"log": [f"判定: 需人工(risk={risk}, amount={amount})"], "decision": "待人工"}
    return {"log": [f"判定: 风险{risk}<{AUTO_APPROVE_RISK} 自动通过"], "decision": "通过"}


# ---------------------------------------------------------------------------
# 4. 人工审批（interrupt）
# ---------------------------------------------------------------------------
def human_approve(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """卡住等人工审批。

    知识点回指：阶段 3 · 课 8「Interrupts 人在环中」
    - interrupt() 抛异常式中断，Resume 时整个节点会**重跑**（课 8 实测：执行 2 次）
    - 所以本节点不能有副作用（不要在这里发短信/打款）
    """
    risk = state.get("risk", 0.0)
    amount = state.get("amount", 0.0)

    # interrupt 的返回值 = Command(resume=...) 传进来的值
    answer = interrupt({
        "question": f"订单 {state['order_id']} 申请退款 {amount} 元，风险分 {risk}，是否批准？",
        "order_id": state["order_id"],
        "amount": amount,
        "risk": risk,
    })

    approved = bool(answer) if isinstance(answer, bool) else str(answer).lower() in (
        "yes", "y", "true", "1", "批准", "同意",
    )
    return {
        "log": [f"人工审批: {'批准' if approved else '驳回'}"],
        "approved": approved,
        "decision": "通过" if approved else "拒绝",
    }


# ---------------------------------------------------------------------------
# 5. 执行退款（有副作用，必须幂等 + 重试）
# ---------------------------------------------------------------------------
def do_refund(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """执行退款。有副作用 → 必须幂等 + 重试策略保守。"""
    deps = get_deps(config)
    key = _idempotency_key(state)
    refund_id = deps.refund.refund(state["order_id"], state["amount"], key)
    return {"log": [f"已退款: {refund_id}"], "refund_id": refund_id}


# ---------------------------------------------------------------------------
# 6. 通知
# ---------------------------------------------------------------------------
def notify(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """通知用户结果。失败不影响主流程（用 try 兜住）。"""
    deps = get_deps(config)
    msg = f"订单 {state['order_id']} 退款{state.get('decision', '未知')}"
    try:
        deps.notifier.notify(state["order_id"], msg)
        return {"log": [f"已通知: {msg}"]}
    except Exception as e:  # 通知失败不该让整单失败
        # 知识点回指：阶段 3 · 课 10 —— 非关键环节的失败要在节点内消化
        return {"log": [f"通知失败(已忽略): {type(e).__name__}: {e}"]}


# ---------------------------------------------------------------------------
# 7. 兜底：拒绝
# ---------------------------------------------------------------------------
def reject(state: RefundState, config: Optional[RunnableConfig] = None) -> dict:
    """拒绝分支的收口。"""
    return {"log": ["工单结束: 拒绝"], "decision": "拒绝"}
