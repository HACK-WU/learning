"""建图：把四个节点串成"回忆 → 抽取 →（确认）→ 写档"。

知识点回指：
- 阶段 1 · 课 3「条件边与循环」——按 need_confirm 分支
- 阶段 2 · 课 6「Store 与命名空间」——compile(store=...) 注入
- 阶段 2 · 课 5「checkpoint 与 thread_id」——compile(checkpointer=...)
- 阶段 3 · 课 8「审批流落地」——interrupt + Command(resume=)

关键点：
- **store 与 checkpointer 是两个独立的东西**，都要在 compile 时传
- store 管"跨会话的用户档案"（user 作用域）
- checkpointer 管"这一轮跑到哪了"（thread 作用域）
"""
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.store.base import BaseStore
from langgraph.store.memory import InMemoryStore

from .nodes import confirm, extract, recall, write_memory
from .state import MemoryState


def route_after_extract(state: MemoryState) -> str:
    """按是否需要人工确认分支。"""
    return "confirm" if state.get("need_confirm") else "write"


def build_graph(
    *,
    checkpointer=None,
    store: BaseStore | None = None,
):
    """构建客服助手图。

    Args:
        checkpointer: 断点续跑用（thread 作用域）。None 则不支持 interrupt 恢复。
        store: 长期记忆柜（user 作用域）。None 则节点里拿到 None（会崩），故默认建一个。
    """
    builder = StateGraph(MemoryState)

    builder.add_node("recall", recall)
    builder.add_node("extract", extract)
    builder.add_node("confirm", confirm)
    builder.add_node("write", write_memory)

    builder.add_edge(START, "recall")
    builder.add_edge("recall", "extract")
    builder.add_conditional_edges(
        "extract",
        route_after_extract,
        {"confirm": "confirm", "write": "write"},
    )
    builder.add_edge("confirm", "write")
    builder.add_edge("write", END)

    return builder.compile(
        checkpointer=checkpointer if checkpointer is not None else InMemorySaver(),
        store=store if store is not None else InMemoryStore(),
    )


# langgraph.json 的 graphs 入口指向它（部署契约）
graph = build_graph()
