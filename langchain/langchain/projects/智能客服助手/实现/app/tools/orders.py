"""订单与物流工具（课 4：@tool 创建工具 / docstring 即工具描述）。

业务数据为内存假数据（演示用）——真实系统应接订单服务 API。
注意：工具返回值一律为「人类可读字符串」或「结构化错误说明」，
不抛异常穿透到 agent 循环（课 4：错误处理的工程实践）。
"""
from langchain.tools import tool

# ---- 演示数据（虚构）--------------------------------------------------
ORDERS: dict[str, dict] = {
    "A1001": {
        "item": "星云智能音箱 Pro",
        "status": "已签收",
        "paid_amount": 399.00,
        "signed_date": "2026-09-12",
    },
    "A1002": {
        "item": "星云无线耳机 Air",
        "status": "已签收",
        "paid_amount": 89.00,
        "signed_date": "2026-09-14",
    },
    "A1003": {
        "item": "星云移动电源 20000mAh",
        "status": "运输中",
        "paid_amount": 129.00,
        "signed_date": None,
    },
    "A1004": {
        "item": "星云高清屏幕贴膜",
        "status": "已签收",
        "paid_amount": 29.00,
        "signed_date": "2026-09-13",
    },
}

LOGISTICS: dict[str, str] = {
    "A1001": "09-10 已揽收 → 09-11 到达杭州转运中心 → 09-12 已签收（本人签收）",
    "A1002": "09-12 已揽收 → 09-13 到达杭州转运中心 → 09-14 已签收（丰巢柜代收）",
    "A1003": "09-15 已揽收 → 09-16 运输中（预计 09-18 送达）",
    "A1004": "09-11 已揽收 → 09-12 到达杭州转运中心 → 09-13 已签收（本人签收）",
}


@tool
def query_order(order_id: str) -> str:
    """根据订单号查询订单状态（商品、实付金额、是否已签收）。"""
    order = ORDERS.get(order_id.upper())
    if not order:
        return f"未找到订单 {order_id}，请核对订单号（格式如 A1001）。"
    signed = order["signed_date"] or "未签收"
    return (
        f"订单 {order_id.upper()}：{order['item']}｜状态：{order['status']}｜"
        f"实付金额：￥{order['paid_amount']:.2f}｜签收日期：{signed}"
    )


@tool
def query_logistics(order_id: str) -> str:
    """根据订单号查询物流轨迹。"""
    track = LOGISTICS.get(order_id.upper())
    if not track:
        return f"订单 {order_id} 暂无物流记录（可能未发货或订单号有误）。"
    return f"订单 {order_id.upper()} 物流轨迹：{track}"
