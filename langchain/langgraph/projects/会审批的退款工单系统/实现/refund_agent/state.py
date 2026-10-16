"""退款工单系统的状态定义。

知识点回指：
- 阶段 1 · 课 3「State 的定义与 reducer」——Annotated + operator.add 累加语义
- 阶段 1 · 课 3「节点返回的是增量不是全量」

关键设计：
- log 用 Annotated[list, operator.add] 累加，否则每次返回会被覆盖（课 3 实测的坑）
- 其余字段是"最后一次写入为准"的覆盖语义
"""
from typing import Annotated, Optional

from operator import add
from typing_extensions import TypedDict


class RefundState(TypedDict):
    """一次退款工单的完整状态。

    字段分三类：
    1. 输入（外部传入，不再修改）：order_id / amount / reason
    2. 流程产物（节点写入）：risk / decision / log / attempts
    3. 控制字段（人为环中与回放用）：approved / refund_id
    """

    # ---- 输入 ----
    order_id: str
    amount: float
    reason: str

    # ---- 流程产物 ----
    # 累加语义：每个节点 return {"log": [...]} 会被追加，而不是覆盖
    log: Annotated[list, add]
    attempts: Annotated[list, add]
    risk: float
    decision: str

    # ---- 控制字段 ----
    approved: bool
    refund_id: str


def empty_state(order_id: str, amount: float, reason: str = "用户申请") -> RefundState:
    """构造一个干净的初始状态（测试与示例都用它，避免漏字段）。"""
    return {
        "order_id": order_id,
        "amount": amount,
        "reason": reason,
        "log": [],
        "attempts": [],
        "risk": 0.0,
        "decision": "",
        "approved": False,
        "refund_id": "",
    }
