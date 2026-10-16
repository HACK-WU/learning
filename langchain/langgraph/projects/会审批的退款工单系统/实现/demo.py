#!/usr/bin/env python3
"""退款工单系统 · 一键演示。

按顺序跑 6 个场景，每个场景演示一组知识点：
  1. 小额自动通过            —— 阶段 1（图与条件边）
  2. 风控抖了能自己好        —— 阶段 3（重试 + 异常类型）
  3. 抖了却抛 ValueError     —— 阶段 3 反例（配了 retry 也不重试）
  4. 大额转人工 → 批准       —— 阶段 3（interrupt + resume）
  5. 回放：看存档点          —— 阶段 3（time-travel）
  6. 流式输出                —— 阶段 2（streaming）+ 阶段 4（SSE 的数据源）

跑法（在项目 `实现/` 目录下）：
    uv run --project <playground路径> python demo.py
"""
from langgraph.checkpoint.memory import InMemorySaver

from refund_agent import RefundService
from refund_agent.clients import FakeRefundClient, FakeRiskClient, FakeRiskClientWrongError
from refund_agent.deps import Deps


def hr(title: str):
    print("\n" + "=" * 62)
    print(f"  {title}")
    print("=" * 62)


def show_log(state: dict):
    for line in state.get("log", []):
        print(f"    · {line}")


# ---------------------------------------------------------------------------
hr("场景 1：小额自动通过（阶段 1 · 图与条件边）")
svc = RefundService(deps=Deps.fake(risk_score=0.3), checkpointer=InMemorySaver())
r = svc.submit("ORD-1", 200.0)
print(f"  结论：{r['decision']}   退款单：{r['refund_id']}")
show_log(r)

# ---------------------------------------------------------------------------
hr("场景 2：风控抖了 2 次，自己重试好了（阶段 3 · 重试）")
deps = Deps.fake()
deps.risk = FakeRiskClient(fail_times=2, score_value=0.3)
svc2 = RefundService(deps=deps)
r2 = svc2.submit("ORD-A", 200.0)
print(f"  结论：{r2['decision']}   风控实际调用：{deps.risk.calls} 次（配了 max_attempts=3）")

# ---------------------------------------------------------------------------
hr("场景 3：同样抖了，却抛 ValueError（阶段 3 · 反例）")
deps3 = Deps.fake()
deps3.risk = FakeRiskClientWrongError(fail_times=1, score_value=0.3)
svc3 = RefundService(deps=deps3)
try:
    svc3.submit("ORD-B", 200.0)
    print("  （不该到这里）")
except Exception as e:
    print(f"  抛出：{type(e).__name__}: {e}")
    print(f"  风控实际调用：{deps3.risk.calls} 次  ← 配了 retry 也没重试！")
    print("  原因：default_retry_on 把 ValueError 当代码 bug，不重试")

# ---------------------------------------------------------------------------
hr("场景 4：大额 2000 转人工 → 批准（阶段 3 · interrupt + resume）")
svc4 = RefundService(deps=Deps.fake(risk_score=0.3), checkpointer=InMemorySaver())
svc4.submit("ORD-2", 2000.0)
st = svc4.get_state("refund-ORD-2")
print(f"  卡在：{st.next}")
intr = st.tasks[0].interrupts[0].value
print(f"  待办：{intr['question']}")

r4 = svc4.approve("refund-ORD-2", True)
print(f"  批准后结论：{r4['decision']}   退款单：{r4['refund_id']}")
show_log(r4)

# ---------------------------------------------------------------------------
hr("场景 5：回放 —— 看这笔工单留了几个存档点（阶段 3 · time-travel）")
hist = svc4.history("refund-ORD-2")
print(f"  存档点数：{len(hist)}")
for i, snap in enumerate(hist):
    nxt = getattr(snap, "next", ()) or ()
    print(f"    [{i}] next={nxt or '(结束)'}  log条数={len(snap.values.get('log', []))}")

# ---------------------------------------------------------------------------
hr("场景 6：流式输出（阶段 2 · streaming / 阶段 4 · SSE 数据源）")
svc6 = RefundService(deps=Deps.fake(risk_score=0.2))
for mode, payload in svc6.stream("ORD-D", 100.0, stream_mode=["updates"]):
    for node_name, delta in payload.items():
        print(f"    event: {mode}  ←  节点 {node_name}")

print("\n" + "=" * 62)
print("  演示结束。跑测试：python -m pytest refund_agent/tests/ -q")
print("=" * 62)
