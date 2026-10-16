"""三层测试：抽取规则 / 记忆门面 / 全图集成。

知识点回指：
- 阶段 4 · 课 12「单元与集成测试」——假服务 + 分层断言

跑法（在 playground 环境）：
    uv run --project <playground> python -m pytest memory_agent/tests/ -q
"""
import pytest

from memory_agent.extract import detect_conflicts, extract_facts, needs_confirm
from memory_agent.graph import build_graph
from memory_agent.service import MemoryService
from memory_agent.state import empty_state
from memory_agent.store import FakeStore, MemStore


# ============ 第 1 层：抽取规则（纯函数，无依赖）============

def test_extract_profile_preference():
    """偏好类事实应抽成语义记忆，且标为高风险（需确认）。"""
    facts = extract_facts("我偏好邮件沟通")
    assert len(facts) == 1
    assert facts[0]["kind"] == "profile"
    assert facts[0]["field"] == "prefers"
    assert facts[0]["risk"] is True


def test_extract_episode_complaint():
    """投诉类事实应抽成情景记忆。"""
    facts = extract_facts("投诉物流太慢")
    assert facts[0]["kind"] == "episode"
    assert facts[0]["field"] == "complaint"


def test_extract_returns_empty_for_noise():
    """没有可抽内容的消息返回空列表，不报错。"""
    assert extract_facts("你好") == []


def test_needs_confirm_only_for_risky():
    """只有高风险事实才触发人工确认。"""
    assert needs_confirm(extract_facts("我偏好邮件沟通")) is True
    assert needs_confirm(extract_facts("买了咖啡")) is False


# ============ 第 2 层：记忆门面（FakeStore 替身）============

def test_namespace_is_user_scoped_not_thread():
    """命名空间第一层必须是 user_id——用 thread_id 会让长期记忆退化。"""
    fake = FakeStore()
    mem = MemStore(fake)
    mem.patch_profile("u1", {"prefers": "邮件"})
    # 同一个 user 换 MemStore 实例（模拟换会话）仍能读到
    assert MemStore(fake).get_profile("u1") == {"prefers": "邮件"}
    # 别的 user 读不到
    assert MemStore(fake).get_profile("u2") == {}


def test_profile_patch_merges_not_overwrites():
    """patch_profile 是合并，不是整体替换。"""
    fake = FakeStore()
    mem = MemStore(fake)
    mem.patch_profile("u1", {"prefers": "邮件"})
    mem.patch_profile("u1", {"nickname": "老张"})
    assert mem.get_profile("u1") == {"prefers": "邮件", "nickname": "老张"}


def test_search_default_limit_is_10():
    """search 默认只返回 10 条——必须显式 limit（课 6 实测的坑）。"""
    fake = FakeStore()
    mem = MemStore(fake)
    for i in range(25):
        mem.add_episode("u1", f"e{i}", {"i": i})
    assert len(mem._store.search(("u1", "episodes"))) == 10
    assert len(mem.recent_episodes("u1", limit=50)) == 25


def test_enabled_rules_filter():
    """禁用的规矩不应出现在 enabled_rules 里。"""
    fake = FakeStore()
    mem = MemStore(fake)
    mem.add_rule("u1", "r1", {"text": "发邮件", "enabled": True})
    mem.add_rule("u1", "r2", {"text": "别打电话", "enabled": False})
    assert len(mem.enabled_rules("u1")) == 1


def test_conflict_detected_when_field_differs():
    """同字段不同值 = 冲突。"""
    conflicts = detect_conflicts(
        [{"kind": "profile", "field": "prefers", "value": "短信", "risk": True}],
        {"prefers": "邮件"},
        [],
    )
    assert len(conflicts) == 1
    assert conflicts[0]["old"] == "邮件"


def test_no_conflict_when_field_absent():
    """档案里没这个字段就不算冲突。"""
    conflicts = detect_conflicts(
        [{"kind": "profile", "field": "prefers", "value": "短信", "risk": True}],
        {},
        [],
    )
    assert conflicts == []


# ============ 第 3 层：全图集成 ============

def test_memory_persists_across_threads():
    """核心验收：换个 thread（新会话）仍记得上次的偏好。"""
    svc = MemoryService()
    r1 = svc.chat("u1", "我偏好邮件沟通", thread_id="sess-mon")
    assert r1["status"] == "pend"          # 高风险 → 卡住等确认
    svc.approve("sess-mon", "confirm")

    # 新会话
    r2 = svc.chat("u1", "买了咖啡", thread_id="sess-fri")
    assert svc.profile("u1")["prefers"] == "邮件"   # 跨会话还在


def test_user_isolation():
    """不同用户的记忆互相隔离。"""
    svc = MemoryService()
    r = svc.chat("uA", "我偏好邮件沟通", thread_id="t-a")
    if r["status"] == "pend":
        svc.approve("t-a", "confirm")
    assert svc.profile("uA")["prefers"] == "邮件"
    assert svc.profile("uB") == {}


def test_reject_does_not_write():
    """人工拒绝后不应写档。"""
    svc = MemoryService()
    r = svc.chat("u1", "我偏好短信沟通", thread_id="t1")
    assert r["status"] == "pend"
    svc.approve("t1", "reject")
    assert "prefers" not in svc.profile("u1")


def test_low_risk_goes_straight_through():
    """低风险事实不需要确认，一轮走完。"""
    svc = MemoryService()
    r = svc.chat("u1", "买了咖啡", thread_id="t1")
    assert r["status"] == "done"
    # 经历写进去了
    from memory_agent.store import MemStore

    eps = MemStore(svc.store).recent_episodes("u1", limit=10)
    assert any(e.get("field") == "purchase" for e in eps)


def test_resume_does_not_replay_extract():
    """关键机制：resume 不重放 interrupt 前的节点，Store 不会重复写。

    （探针实测结论：resume 后 counter 保持 {n: 1}）
    """
    svc = MemoryService()
    r = svc.chat("u1", "我偏好邮件沟通", thread_id="t1")
    assert r["status"] == "pend"
    svc.approve("t1", "confirm")
    # 只写了一次，档案是单值不是累加
    assert svc.profile("u1")["prefers"] == "邮件"


def test_trace_accumulates():
    """trace 用 add reducer，应累加而不是覆盖。"""
    svc = MemoryService()
    r = svc.chat("u1", "买了咖啡", thread_id="t1")
    assert r["status"] == "done"
    assert len(r["trace"]) >= 3     # recall / extract / write


def test_history_has_checkpoints():
    """回放：这一轮应留下多个存档点。"""
    svc = MemoryService()
    svc.chat("u1", "买了咖啡", thread_id="t1")
    hist = svc.history("t1")
    assert len(hist) >= 3


def test_stream_yields_node_updates():
    """流式输出：每个节点一个 updates 事件。"""
    svc = MemoryService()
    events = list(svc.stream("u1", "买了咖啡", thread_id="t-stream"))
    assert len(events) >= 3
    names = [list(e.keys())[0] for e in events if isinstance(e, dict)]
    assert "recall" in names


def test_graph_builds_without_store_arg():
    """不传 store 时不应崩（build_graph 自建 InMemoryStore）。"""
    g = build_graph()
    assert g is not None


def test_empty_state_has_all_fields():
    """empty_state 必须给全字段，否则节点访问会 KeyError。"""
    s = empty_state("u1", "hi")
    for k in ("user_id", "message", "candidates", "conflicts", "need_confirm", "decision", "trace", "reply"):
        assert k in s
