"""退款工单图：把节点焊成一张图。

知识点回指（本文件是跨阶段整合最密集的地方）：
- 阶段 1 · 课 3「条件边」——route_after_decide 决定去向
- 阶段 2 · 课 4「Command」——同时更新状态并跳转（decide 一步到位）
- 阶段 2 · 课 5「checkpointer」——编译期传入，决定能不能断点续跑
- 阶段 3 · 课 10「RetryPolicy / error_handler / 子图」——风控子图封装
- 阶段 4 · 课 12「项目结构与 langgraph.json」——graph 变量名在这里

⚠️ 与官方 create_react_agent 的区别：这里的控制流是**显式**写出来的，
每个分支你都能在 Studio 里看到，而不是藏在预置 agent 内部。
"""
from __future__ import annotations

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import RetryPolicy

from .deps import CONFIG_KEY, Deps
from .nodes.flow import (
    AUTO_APPROVE_RISK,
    AUTO_REJECT_RISK,
    decide,
    do_refund,
    human_approve,
    notify,
    reject,
    score_risk,
    validate,
)
from .state import RefundState

# ---------------------------------------------------------------------------
# 重试策略
# 知识点回指：阶段 3 · 课 10（实测：默认 retry_on 挑异常类型）
# ---------------------------------------------------------------------------
# 风控是只读接口，抖了重试很安全
RISK_RETRY = RetryPolicy(max_attempts=3)

# 退款有副作用：重试次数更保守，且依赖幂等键（见 nodes/flow.py::_idempotency_key）
REFUND_RETRY = RetryPolicy(max_attempts=2)


# ---------------------------------------------------------------------------
# 路由
# ---------------------------------------------------------------------------
def route_after_validate(state: RefundState) -> str:
    """校验不通过直接结束，不浪费风控调用。"""
    if state.get("decision") == "拒绝":
        return "reject"
    return "score_risk"


def route_after_decide(state: RefundState) -> str:
    """按判定结果分三路：通过 / 待人工 / 拒绝。"""
    d = state.get("decision", "")
    if d == "通过":
        return "do_refund"
    if d == "待人工":
        return "human_approve"
    return "reject"


# ---------------------------------------------------------------------------
# 建图
# ---------------------------------------------------------------------------
def build_graph(checkpointer=None, store=None):
    """构建退款工单图。

    checkpointer: 传入即可断点续跑（阶段 2 · 课 5）
                  不传 → interrupt 能停但**不能恢复**（阶段 3 · 课 8 实测）
    store:        长期记忆（阶段 2 · 课 6），本项目存"用户历史退款画像"
    """
    builder = StateGraph(RefundState)

    # --- 节点 ---
    builder.add_node("validate", validate)
    builder.add_node("score_risk", score_risk, retry_policy=RISK_RETRY)
    builder.add_node("decide", decide)
    builder.add_node("human_approve", human_approve)
    builder.add_node("do_refund", do_refund, retry_policy=REFUND_RETRY)
    builder.add_node("notify", notify)
    builder.add_node("reject", reject)

    # --- 边 ---
    builder.add_edge(START, "validate")
    builder.add_conditional_edges(
        "validate",
        route_after_validate,
        {"score_risk": "score_risk", "reject": "reject"},
    )
    builder.add_edge("score_risk", "decide")
    builder.add_conditional_edges(
        "decide",
        route_after_decide,
        {"do_refund": "do_refund", "human_approve": "human_approve", "reject": "reject"},
    )
    builder.add_edge("human_approve", "do_refund")
    builder.add_edge("do_refund", "notify")
    builder.add_edge("notify", END)
    builder.add_edge("reject", END)

    return builder.compile(checkpointer=checkpointer, store=store)


# ---------------------------------------------------------------------------
# 默认图：给 langgraph.json 用（必须有 checkpointer，否则 interrupt 无法恢复）
# ---------------------------------------------------------------------------
def make_default_graph():
    """带默认内存 checkpointer 的图（本地 dev 用）。

    ⚠️ InMemorySaver 进程一停就没了 —— 生产要换 SqliteSaver / PostgresSaver。
    知识点回指：阶段 2 · 课 5「checkpoint 与后端选型」
    """
    return build_graph(checkpointer=InMemorySaver())


graph = make_default_graph()
