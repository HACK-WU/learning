"""父图：Send 扇出到各来源子图 → 汇总 → 出报告。

知识点回指：
- 阶段 1 · 课 3「条件边与循环」
- 阶段 2 · 课 4「Pregel 执行模型 / Send 动态扇出」
- 阶段 3 · 课 10「子图与状态隔离」——父子只传共有字段

⚠️ 实测确认（探针 probe_subgraph.py）：
- 子图**拿不到**父图私有字段（parent_only 不在子图 state 里）
- 父图**拿不到**子图私有字段（child_only 不在父图 state 里）
- 只有两边都声明的字段（shared）会传递
"""
from typing import Any

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.store.memory import InMemoryStore
from langgraph.types import Send

from .sources import SourceRegistry
from .state import ResearchState, empty_state
from .subgraph import build_source_subgraph


def build_graph(*, registry: SourceRegistry | None = None, checkpointer=None, store=None):
    """构建调研流水线。

    Args:
        registry: 来源注册表。None 则用空注册表（调用方一般要传）。
        checkpointer: 断点续跑用。
        store: 长期记忆用（本项目未用，留接口）。
    """
    reg = registry or SourceRegistry()
    sub = build_source_subgraph(reg)

    def fanout(state: ResearchState) -> list[Send]:
        """扇出：每个来源一个子图实例，并行跑。

        实测：4 个来源 → 4 个任务并行，结果全部汇总回来。
        """
        return [
            Send("investigate", {"source": s, "query": state["query"], "scratch": []})
            for s in state["sources"]
        ]

    def investigate(state: dict[str, Any]) -> dict:
        """包一层子图调用：把子图结论转成父图的 results。

        子图返回 {result: ..., scratch: [...]}，
        父图只声明了 results / trace，所以 scratch 自动被丢弃（实测确认）。
        """
        out = sub.invoke({"source": state["source"], "query": state["query"], "scratch": []})
        r = out.get("result")
        if not r:
            return {"trace": [f"{state['source']}: 无结论"]}
        return {
            "results": [r],
            "trace": [f"{state['source']}: ok={r['ok']}"],
        }

    def aggregate(state: ResearchState) -> dict:
        """汇总：分开成功与失败，判断整体是否可用。"""
        succeeded = [r["source"] for r in state["results"] if r["ok"]]
        failed = [r["source"] for r in state["results"] if not r["ok"]]
        return {
            "succeeded": succeeded,
            "failed": failed,
            "trace": [f"汇总: 成功{len(succeeded)} 失败{len(failed)}"],
        }

    def report(state: ResearchState) -> dict:
        """出报告。降级策略：有成功就出报告，全失败才说没查到。"""
        if not state["succeeded"]:
            return {
                "report": f"全部 {len(state['failed'])} 个来源都不可用：{', '.join(state['failed'])}",
                "trace": ["报告: 全失败"],
            }

        lines = [f"调研「{state['query']}」结果：", ""]
        for r in state["results"]:
            if r["ok"]:
                lines.append(f"  ✅ {r['source']}: {r['data']}")
            else:
                lines.append(f"  ⚠️ {r['source']}: 不可用（{r['error'][:40]}）")
        lines.append("")
        lines.append(f"覆盖 {len(state['succeeded'])}/{len(state['results'])} 个来源")
        if state["failed"]:
            lines.append(f"⚠️ 以下来源降级处理：{', '.join(state['failed'])}")

        return {"report": "\n".join(lines), "trace": ["报告: 已生成"]}

    b = StateGraph(ResearchState)
    b.add_node("investigate", investigate)
    b.add_node("aggregate", aggregate)
    b.add_node("report", report)

    b.add_conditional_edges(START, fanout, ["investigate"])
    b.add_edge("investigate", "aggregate")
    b.add_edge("aggregate", "report")
    b.add_edge("report", END)

    return b.compile(
        checkpointer=checkpointer if checkpointer is not None else InMemorySaver(),
        store=store if store is not None else InMemoryStore(),
    )


def run(query: str, sources: list[str], registry: SourceRegistry, thread_id: str = "t1"):
    """便捷入口：一次跑完整条流水线。"""
    g = build_graph(registry=registry)
    return g.invoke(empty_state(query, sources), {"configurable": {"thread_id": thread_id}})
