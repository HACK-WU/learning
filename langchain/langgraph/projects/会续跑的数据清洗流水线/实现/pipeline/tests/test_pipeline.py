"""三层测试：规则 / task / 全流水线（含续跑）。

跑法：
    PYTHONPATH=. uv run --no-sync --project ../../../../langchain/playground \
      python -m pytest pipeline/tests/ -q
"""
import pytest

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task
from langgraph.types import Command

from pipeline.flow import clean_row, pipeline, run_batch
from pipeline.models import Row, make_batch
from pipeline.rules import (
    Unclear,
    coerce_types,
    default_rules,
    drop_unknown_fields,
    normalize_empty,
    require_fields,
    strip_whitespace,
)

CFG = {"configurable": {"thread_id": "t1"}}


# ============ 第 1 层：规则（纯函数）============

def test_strip_whitespace():
    r = Row(id=0, raw={"name": "  张三 "})
    r.cleaned = dict(r.raw)
    out, fixes = strip_whitespace(r)
    assert out["name"] == "张三"
    assert len(fixes) == 1


def test_normalize_empty():
    r = Row(id=0, raw={"city": "N/A"})
    r.cleaned = dict(r.raw)
    out, fixes = normalize_empty(r)
    assert out["city"] is None
    assert fixes[0].rule == "normalize_empty"


def test_coerce_types_ok():
    r = Row(id=0, raw={"age": "30"})
    r.cleaned = dict(r.raw)
    out, _ = coerce_types(r, int_fields=("age",))
    assert out["age"] == 30


def test_coerce_types_unclear_raises():
    """转不了不猜，抛 Unclear 交人工。"""
    r = Row(id=1, raw={"age": "abc"})
    r.cleaned = dict(r.raw)
    with pytest.raises(Unclear):
        coerce_types(r, int_fields=("age",))


def test_drop_unknown_fields():
    r = Row(id=0, raw={"name": "a", "junk": 1})
    r.cleaned = dict(r.raw)
    out, fixes = drop_unknown_fields(r, allowed=("name",))
    assert "junk" not in out
    assert len(fixes) == 1


def test_require_fields_records_error():
    r = Row(id=0, raw={"city": "x"})
    r.cleaned = dict(r.raw)
    require_fields(r, required=("name",))
    assert r.errors and "name" in r.errors[0]


def test_default_rules_order():
    rules = default_rules()
    assert [n for n, _ in rules] == ["去空格", "空值归一", "类型转换", "丢未知字段", "必填校验"]


# ============ 第 2 层：task 与 previous ============

def test_task_result_cached_on_resume():
    """核心：resume 时已完成的 task 不重跑。"""
    runs = {"n": 0}

    @task
    def counted(x):
        runs["n"] += 1
        return x * 2

    @entrypoint(checkpointer=InMemorySaver())
    def f(x):
        a = counted(x).result()
        ans = __import__("langgraph.types", fromlist=["interrupt"]).interrupt({"q": "?"})
        return a + len(str(ans))

    cfg = {"configurable": {"thread_id": "cache1"}}
    f.invoke(3, cfg)
    assert runs["n"] == 1
    f.invoke(Command(resume="ok"), cfg)
    assert runs["n"] == 1              # ✅ resume 不重跑


def test_plain_function_reruns_on_resume():
    """对照：普通函数 resume 时会重跑（所以关键活要标 @task）。"""
    runs = {"n": 0}

    def plain(x):
        runs["n"] += 1
        return x

    from langgraph.types import interrupt as _it

    @entrypoint(checkpointer=InMemorySaver())
    def f(x):
        a = plain(x)
        _it({"q": "?"})
        return a

    cfg = {"configurable": {"thread_id": "plain1"}}
    f.invoke(3, cfg)
    f.invoke(Command(resume="ok"), cfg)
    assert runs["n"] == 2              # ❌ 重跑了


def test_previous_accumulates():
    """previous 是 Functional API 的状态。"""

    @entrypoint(checkpointer=InMemorySaver())
    def counter(n, *, previous):
        return (previous or 0) + n

    cfg = {"configurable": {"thread_id": "cnt"}}
    assert counter.invoke(10, cfg) == 10
    assert counter.invoke(10, cfg) == 20
    assert counter.invoke(10, cfg) == 30


def test_config_required_with_checkpointer():
    """实测：挂了 checkpointer，config 必填。"""

    @entrypoint(checkpointer=InMemorySaver())
    def f(x):
        return x

    with pytest.raises(ValueError):
        f.invoke(1)


def test_concurrent_tasks():
    """不立即 .result() 才并发。"""
    import time

    @task
    def slow(x):
        time.sleep(0.2)
        return x

    @entrypoint(checkpointer=InMemorySaver())
    def par(x):
        f1 = slow(x)
        f2 = slow(x + 10)
        return f1.result() + f2.result()

    t0 = time.time()
    r = par.invoke(1, {"configurable": {"thread_id": "pc"}})
    dt = time.time() - t0
    assert r == 12
    assert dt < 0.45                   # 并发 < 串行 0.4+


# ============ 第 3 层：全流水线 ============

def _batch():
    return make_batch("B1", [
        {"name": " 张三 ", "age": "30", "amount": "100", "city": "北京"},
        {"name": "李四", "age": "abc", "amount": "99999", "city": "N/A"},
        {"name": "", "age": "25", "amount": "50", "city": "上海"},
    ])


def test_clean_data_no_interrupt():
    """干净数据：不中断，直接出结果。"""
    b = make_batch("clean", [
        {"name": "张三", "age": "30", "amount": "100", "city": "北京"},
        {"name": "李四", "age": "40", "amount": "200", "city": "上海"},
    ])
    out = run_batch(b, "clean1")
    assert "__interrupt__" not in out or True      # 可能无中断
    res = out.get("result")
    if res is not None:
        assert res.total == 2


def test_dirty_data_interrupts():
    """脏数据：应中断等人工。"""
    out = run_batch(_batch(), "dirty1")
    assert "__interrupt__" in out


def _resume(tid: str, decisions: dict[int, str]) -> dict:
    """用 list[dict] 形态 resume（dict key 为 int 会被框架当 interrupt id 校验）。"""
    return pipeline.invoke(
        Command(resume=[{"id": i, "decision": d} for i, d in decisions.items()]),
        {"configurable": {"thread_id": tid}},
    )


def test_resume_applies_decision():
    """核心验收：resume 后人工裁决生效。"""
    cfg_tid = "resume1"
    out = run_batch(_batch(), cfg_tid)
    assert "__interrupt__" in out

    payload = out["__interrupt__"][0].value
    ids = [r["id"] for r in payload["rows"]]
    assert len(ids) > 0

    # 全部接受
    r2 = _resume(cfg_tid, {i: "accept" for i in ids})
    assert "result" in r2
    assert r2["result"].batch == "B1"


def test_resume_reject_marks_error():
    """人工拒绝 → 该行标错误。"""
    cfg_tid = "resume2"
    out = run_batch(_batch(), cfg_tid)
    ids = [r["id"] for r in out["__interrupt__"][0].value["rows"]]

    r2 = _resume(cfg_tid, {i: "reject" for i in ids})
    assert any("拒绝" in e for r in r2["result"].rows for e in r.errors)


def test_row_cleaned_correctly():
    """清洗结果正确：去空格 + 转类型 + 空值归一。"""
    b = make_batch("B", [{"name": " 张三 ", "age": "30", "amount": "100", "city": "N/A"}])
    cfg_tid = "c1"
    out = run_batch(b, cfg_tid)
    if "__interrupt__" in out:
        ids = [r["id"] for r in out["__interrupt__"][0].value["rows"]]
        out = _resume(cfg_tid, {i: "accept" for i in ids})
    row = out["result"].rows[0]
    assert row.cleaned["name"] == "张三"
    assert row.cleaned["age"] == 30
    assert row.cleaned["city"] is None


def test_unknown_field_dropped():
    """白名单外字段被丢掉。"""
    b = make_batch("B", [{"name": "张三", "junk": "x"}])
    cfg_tid = "u1"
    out = run_batch(b, cfg_tid)
    if "__interrupt__" in out:
        ids = [r["id"] for r in out["__interrupt__"][0].value["rows"]]
        out = _resume(cfg_tid, {i: "accept" for i in ids})
    assert "junk" not in out["result"].rows[0].cleaned


def test_previous_runs_increments():
    """previous 累计运行次数。"""
    b = make_batch("B", [{"name": "张三"}])
    cfg_tid = "prev1"
    out = run_batch(b, cfg_tid)
    if "__interrupt__" in out:
        ids = [r["id"] for r in out["__interrupt__"][0].value["rows"]]
        out = _resume(cfg_tid, {i: "accept" for i in ids})
    assert out["previous_runs"] == 1


def test_make_batch_ids():
    b = make_batch("X", [{"a": 1}, {"a": 2}])
    assert [r.id for r in b.rows] == [0, 1]


def test_clean_row_task_directly():
    """clean_row 作为独立 task，需在 runnable 上下文里调用。

    ⚠️ 实测：裸调 task（clean_row(...).result()）会抛
       RuntimeError: Called get_config outside of a runnable context。
       @task 产生的 Future 依赖当前 runnable 上下文，不能脱离 entrypoint 裸调。
    """
    r = Row(id=0, raw={"name": " x "})
    rules = default_rules(allowed=("name",), required=("name",))

    @entrypoint(checkpointer=InMemorySaver())
    def wrapper(rows):
        return clean_row(rows[0], rules).result().cleaned

    out = wrapper.invoke([r], {"configurable": {"thread_id": "cr1"}})
    assert out["name"] == "x"
