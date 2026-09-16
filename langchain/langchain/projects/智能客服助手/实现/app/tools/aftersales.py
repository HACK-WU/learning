"""售后工具（课 4 工具设计 + 课 10 人机协同的落地）。

三个工具的风险等级不同，护栏策略也不同：
- create_return_request：中风险，自动执行（写审计轨迹）
- process_refund：高风险（钱不可逆）——金额分级审批：
    金额 >= 阈值 → 人工审批（由 agent 装配层的 HITL 中间件拦截）
    金额 <  阈值 → 直通执行
- escalate_to_human：转人工（handoff 概念的最小实现，课 12）
"""
from langchain.tools import tool

from app.tools.orders import ORDERS

# 执行账本：记录真实发生的退款/退货动作（演示与测试断言用；真实系统应写数据库/审计日志）
ACTIONS: list[dict] = []


@tool
def create_return_request(order_id: str, reason: str) -> str:
    """为指定订单提交退货申请。reason 为退货原因（如：质量问题 / 七天无理由 / 尺寸不符）。"""
    order = ORDERS.get(order_id.upper())
    if not order:
        return f"未找到订单 {order_id}，请核对订单号后再试。"
    if order["status"] != "已签收":
        return f"订单 {order_id.upper()} 当前状态为「{order['status']}」，签收后才能申请退货。"

    request_id = f"R{len(ACTIONS) + 1:04d}"
    ACTIONS.append({"type": "return", "order_id": order_id.upper(), "reason": reason})
    return (
        f"已为订单 {order_id.upper()} 提交退货申请（单号 {request_id}）。"
        f"请在 7 日内寄回商品，质检通过后发起退款。"
    )


@tool
def process_refund(order_id: str, amount: float) -> str:
    """为指定订单发起退款。amount 必须与订单实付金额一致（金额较大时需人工审批）。"""
    order = ORDERS.get(order_id.upper())
    if not order:
        return f"未找到订单 {order_id}，请核对订单号后再试。"

    # 防幻觉护栏：金额必须与订单实付金额一致（课 10 护栏思维的工程落地）
    expected = order["paid_amount"]
    if abs(amount - expected) > 0.01:
        return (
            f"退款金额校验不通过：订单 {order_id.upper()} 实付 ￥{expected:.2f}，"
            f"提交的退款金额为 ￥{amount:.2f}。请核对金额后重新提交。"
        )

    ACTIONS.append({"type": "refund", "order_id": order_id.upper(), "amount": amount})
    return (
        f"已为订单 {order_id.upper()} 发起退款 ￥{amount:.2f}（原路退回），"
        f"预计 1-3 个工作日到账。"
    )


@tool
def escalate_to_human(reason: str) -> str:
    """将当前会话转接人工客服（当用户强烈不满、投诉、或问题超出处理范围时使用）。"""
    ACTIONS.append({"type": "escalate", "reason": reason})
    return (
        "已为您创建人工工单（编号 T-20260916-01），人工客服将在 5 分钟内接入。"
        "如需补充材料，可直接发送给人工客服。"
    )
