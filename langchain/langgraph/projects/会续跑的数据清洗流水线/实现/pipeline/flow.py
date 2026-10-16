"""Functional API 流水线：@entrypoint + @task，会暂停、会续跑。

知识点回指：
- 阶段 3 · 课 11「@entrypoint / @task 模型」——task 结果进存档点
- 阶段 3 · 课 11「previous 参数」——跨调用累计
- 阶段 3 · 课 8「Interrupts 人在环中」——interrupt 卡住等人工
- 阶段 3 · 课 9「Time-travel 回放与分叉」

🔴 本项目实测出的关键事实（langgraph 1.2.11，比课 11 更精确）：

课 11 说「@task 标注的函数其结果会写进存档点」——这句话容易读成
"重跑会复用"。实测澄清如下：

| 场景 | 已完成的 task | 含 interrupt 的 task |
|------|--------------|---------------------|
| **resume**（Command(resume=...)） | ✅ **不重跑**（复用存档） | ❌ **重跑**（要拿到人工输入才能继续） |
| **同 thread 再 invoke**（非 resume） | ❌ 重跑 | ❌ 重跑 |

👉 一句话：**"写进存档点"的价值在 resume 时体现，不是在同 thread 重跑时。**
   同 thread 再 invoke 是**新的一次执行**，全部重来。

这正是"续跑"这个词的确切含义：卡住 → 人工确认 → **前面的活不白干**，
但卡住的那一格本身要重跑（因为它需要人工输入才能算出结果）。

另一个实测：普通函数（没标 @task）在 resume 时**也会重跑**——
所以"哪些活不白干"完全由 @task 决定，普通函数一律重来。
"""
from typing import Any

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.func import entrypoint, task
from langgraph.types import Command, interrupt

from .models import Batch, PipelineResult, Row, StageReport
from .rules import Fix
from .rules import Rule, Unclear, default_rules


# ============================================================
# @task：每个 task 的结果进存档点
# ============================================================


@task
def clean_row(row: Row, rules: list[tuple[str, Rule]]) -> Row:
    """清洗一行。标了 @task → 结果进存档点，resume 时不重跑。"""
    row.cleaned = dict(row.raw)
    applied: list[Fix] = []

    for name, rule in rules:
        try:
            row.cleaned, fixes = rule(row)
            applied.extend(fixes)
        except Unclear as e:
            row.errors.append(f"[{name}] {e}")

    return row


@task
def detect_outliers(rows: list[Row], *, field: str, max_val: float) -> list[Row]:
    """标记异常值（不删，标记出来交人工看）。

    也是 @task —— 这活重，不该白干第二遍。
    """
    for r in rows:
        v = r.cleaned.get(field)
        if isinstance(v, (int, float)) and v > max_val:
            r.errors.append(f"{field}={v} 超过上限 {max_val}，需人工确认")
    return rows


@entrypoint(checkpointer=InMemorySaver())
def pipeline(batch: Batch, *, previous: Any = None) -> dict:
    """数据清洗主流程。

    控制流就是普通 Python：先并发洗每一行，再汇总，再人工复核。

    暂停点：有"需人工确认"的行时 interrupt，人工裁决后**续跑**——
    前面 clean_row / detect_outliers 的结果从存档点取，不重算。
    """
    rules = default_rules(
        int_fields=("age", "amount"),
        allowed=("name", "age", "amount", "city"),
        required=("name",),
    )

    # ① 并发清洗：先全提交，再统一收（课 11 实测：这样才并发）
    futures = [clean_row(r, rules) for r in batch.rows]
    cleaned = [f.result() for f in futures]

    # ② 异常检测（也是 task，resume 时不用重算）
    checked = detect_outliers(cleaned, field="amount", max_val=10000).result()

    # ③ 汇总哪些要人工看
    needs = [r.id for r in checked if r.errors]

    # ④ 暂停：有人要确认就 interrupt
    #    ⚠️ 实测：interrupt 所在的这次执行在 resume 时会**重跑**，
    #       所以 interrupt 前后的纯计算要尽量放进 @task。
    #
    #    ⚠️ 实测第二个硬约束：Command(resume=...) 若传 dict，框架会检查
    #       每个 key 是否为 32 位 hex（interrupt id），行 id 是 int 会直接
    #       TypeError（pregel/_loop.py: is_xxh3_128_hexdigest）。
    #       所以裁决用 list[dict] 传，不用 dict[int, str]。
    review: dict[int, str] = {}
    if needs:
        payload = {
            "batch": batch.name,
            "rows": [
                {"id": r.id, "errors": r.errors, "data": r.cleaned}
                for r in checked
                if r.errors
            ],
        }
        answer = interrupt(payload)
        # resume 时从这里继续；answer 是人工的裁决
        # 支持两种形态：list[{"id":..,"decision":..}] 或 {"decisions": [...]}
        if isinstance(answer, list):
            review = {d["id"]: d["decision"] for d in answer if "id" in d}
        elif isinstance(answer, dict) and "decisions" in answer:
            review = {d["id"]: d["decision"] for d in answer["decisions"] if "id" in d}

    # ⑤ 应用人工裁决
    final: list[Row] = []
    for r in checked:
        if r.id in review:
            decision = review[r.id]
            if decision == "accept":
                r.errors = [e for e in r.errors if "需人工确认" not in e]
            elif decision == "reject":
                r.errors.append("人工判定：拒绝")
        final.append(r)

    succeeded = sum(1 for r in final if r.ok)
    stages = [
        StageReport("清洗", len(cleaned), sum(1 for r in cleaned if r.cleaned != r.raw), 0),
        StageReport("异常检测", len(checked), 0, sum(1 for r in checked if r.errors)),
        StageReport("人工复核", len(review), 0, 0),
    ]

    result = PipelineResult(
        batch=batch.name,
        total=len(final),
        succeeded=succeeded,
        failed=len(final) - succeeded,
        stages=stages,
        rows=final,
        needs_review=needs,
    )

    return {
        "result": result,
        "previous_runs": (previous or 0) + 1 if isinstance(previous, int) else 1,
    }


def run_batch(batch: Batch, thread_id: str = "t1") -> dict:
    """便捷入口：跑一批。

    ⚠️ 实测：Functional API 挂了 checkpointer 后 **config 必填**
    （不传直接 ValueError，Graph API 不传也能跑）——所以这里必传 thread_id。
    同 thread_id 再跑是**新的一次执行**，前面的 task 会重算；
    要"续跑"得用 `Command(resume=...)`。
    """
    return pipeline.invoke(batch, {"configurable": {"thread_id": thread_id}})


def resume_batch(thread_id: str, decisions: dict[int, str]) -> dict:
    """人工裁决后续跑。

    ⚠️ 实测：裁决必须用 **list[dict]** 传（见 flow 里的说明）。
    直接传 `dict[int, str]` 会被框架当成 interrupt-id 映射，
    key 是 int 时抛 TypeError。
    """
    return pipeline.invoke(
        Command(resume=[{"id": i, "decision": d} for i, d in decisions.items()]),
        {"configurable": {"thread_id": thread_id}},
    )
