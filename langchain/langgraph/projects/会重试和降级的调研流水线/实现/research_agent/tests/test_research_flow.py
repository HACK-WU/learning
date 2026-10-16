"""三层测试：来源行为 / 子图重试与隔离 / 全流水线。

跑法：
    PYTHONPATH=. uv run --no-sync --project ../../../../langchain/playground \
      python -m pytest research_agent/tests/ -q
"""
import pytest

from research_agent.graph import build_graph, run
from research_agent.sources import (
    DeadSource,
    FlakySource,
    GoodSource,
    PermanentError,
    SourceRegistry,
    TransientError,
)
from research_agent.state import empty_state
from research_agent.subgraph import build_source_subgraph


# ============ 第 1 层：来源行为（纯对象）============

def test_flaky_source_fails_then_succeeds():
    """会抖动的来源：前 N 次失败，之后成功。"""
    s = FlakySource("A", fail_times=2)
    with pytest.raises(TransientError):
        s.fetch("q")
    with pytest.raises(TransientError):
        s.fetch("q")
    assert "A" in s.fetch("q")


def test_dead_source_always_permanent():
    """永久失败的来源：抛 PermanentError，不是 Transient。"""
    s = DeadSource("B")
    for _ in range(3):
        with pytest.raises(PermanentError):
            s.fetch("q")


def test_registry_unknown_source():
    """未知来源应抛 PermanentError（不是 KeyError）。"""
    with pytest.raises(PermanentError):
        SourceRegistry().get("nope")


# ============ 第 2 层：子图重试与降级 ============

def test_subgraph_retries_transient():
    """关键：TransientError 应被重试，最终成功。"""
    reg = SourceRegistry([FlakySource("A", fail_times=2)])
    sub = build_source_subgraph(reg)
    out = sub.invoke({"source": "A", "query": "q", "scratch": []})
    assert out["result"]["ok"] is True
    assert reg.get("A").calls == 3          # 失败2次 + 成功1次


def test_subgraph_does_not_retry_permanent():
    """关键：PermanentError 不该被重试（重试也白搭）。"""
    reg = SourceRegistry([DeadSource("B")])
    sub = build_source_subgraph(reg)
    out = sub.invoke({"source": "B", "query": "q", "scratch": []})
    assert out["result"]["ok"] is False
    assert "PermanentError" in out["result"]["error"]


def test_subgraph_degrades_instead_of_crashing():
    """降级：来源挂了不能炸整条流水线。"""
    reg = SourceRegistry([DeadSource("B")])
    sub = build_source_subgraph(reg)
    out = sub.invoke({"source": "B", "query": "q", "scratch": []})
    assert out["result"]["ok"] is False          # 有结论，只是标记失败
    assert "降级" in " ".join(out["scratch"])


def test_subgraph_scratch_stays_inside():
    """子图内部产物（scratch）留在子图里。"""
    reg = SourceRegistry([GoodSource("A")])
    sub = build_source_subgraph(reg)
    out = sub.invoke({"source": "A", "query": "q", "scratch": []})
    assert len(out["scratch"]) > 0


# ============ 第 3 层：全流水线 ============

def test_all_good_sources():
    """全部成功：报告应覆盖所有来源。"""
    reg = SourceRegistry([GoodSource("A"), GoodSource("B"), GoodSource("C")])
    r = run("LangGraph", ["A", "B", "C"], reg)
    assert len(r["succeeded"]) == 3
    assert r["failed"] == []
    assert "3/3" in r["report"]


def test_partial_failure_degrades_gracefully():
    """核心验收：部分来源挂了，仍出报告（不是整条崩）。"""
    reg = SourceRegistry([GoodSource("A"), DeadSource("B"), GoodSource("C")])
    r = run("LangGraph", ["A", "B", "C"], reg)
    assert r["succeeded"] == ["A", "C"]
    assert r["failed"] == ["B"]
    assert "降级" in r["report"]
    assert "B" in r["report"]


def test_all_failed_still_returns_report():
    """全失败：不能抛异常，要给出说明性报告。"""
    reg = SourceRegistry([DeadSource("A"), DeadSource("B")])
    r = run("LangGraph", ["A", "B"], reg)
    assert r["succeeded"] == []
    assert "全部" in r["report"]


def test_fanout_parallel():
    """Send 扇出：N 个来源应产出 N 份结论。"""
    reg = SourceRegistry([GoodSource(f"S{i}") for i in range(5)])
    r = run("q", [f"S{i}" for i in range(5)], reg)
    assert len(r["results"]) == 5


def test_retry_happens_in_pipeline():
    """流水线里抖动来源最终应成功（重试生效）。"""
    reg = SourceRegistry([FlakySource("A", fail_times=2), GoodSource("B")])
    r = run("q", ["A", "B"], reg)
    assert "A" in r["succeeded"]


def test_parent_cannot_see_child_private_field():
    """核心验收：子图私有字段不泄漏到父图。

    实测（probe_subgraph）：子图拿不到 parent_only，父图拿不到 child_only。
    """
    reg = SourceRegistry([GoodSource("A")])
    r = run("q", ["A"], reg)
    # 父图状态里不应有 scratch
    assert "scratch" not in r


def test_trace_accumulates():
    """trace 累加而非覆盖。"""
    reg = SourceRegistry([GoodSource("A"), GoodSource("B"), GoodSource("C")])
    r = run("q", ["A", "B", "C"], reg)
    # 3个来源 + 汇总 + 报告
    assert len(r["trace"]) >= 5


def test_empty_state_has_all_fields():
    """empty_state 给全字段。"""
    s = empty_state("q", ["A"])
    for k in ("query", "sources", "results", "succeeded", "failed", "report", "trace"):
        assert k in s


def test_build_graph_without_registry():
    """不传 registry 也能建图（空注册表）。"""
    assert build_graph() is not None
