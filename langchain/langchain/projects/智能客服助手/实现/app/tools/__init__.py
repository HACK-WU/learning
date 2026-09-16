"""工具集（课 4：用 @tool 创建工具 / 工具返回值与错误处理）。

对外导出 ALL_TOOLS，供 agent 组装使用。
"""
from app.tools.aftersales import create_return_request, escalate_to_human, process_refund
from app.tools.knowledge import search_policies
from app.tools.orders import query_logistics, query_order

ALL_TOOLS = [
    query_order,
    query_logistics,
    create_return_request,
    process_refund,
    search_policies,
    escalate_to_human,
]
