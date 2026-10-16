"""六个演示场景——每个都对应一个知识点。

跑法（在 playground 环境，项目实现目录）：
    PYTHONPATH=. uv run --no-sync --project <playground> python demo.py
"""
from memory_agent.service import MemoryService
from memory_agent.store import MemStore


def line(t: str) -> None:
    print(f"\n{'=' * 60}\n{t}\n{'=' * 60}")


def main() -> None:
    line("场景 1：新用户说偏好 → 高风险，卡住等确认")
    svc = MemoryService()
    r = svc.chat("u1", "我偏好邮件沟通", thread_id="sess-1")
    print("  status:", r["status"])
    print("  question:", r.get("question", {}).get("question"))
    print("  candidates:", [(c["field"], c["value"]) for c in r["question"]["candidates"]])

    line("场景 2：人工确认后续跑 → 写档")
    r2 = svc.approve("sess-1", "confirm")
    print("  status:", r2["status"])
    print("  reply:", r2["reply"])
    print("  trace:", r2["trace"])
    print("  profile:", svc.profile("u1"))

    line("场景 3：换个会话（新 thread）→ 还记得吗？")
    r3 = svc.chat("u1", "买了咖啡", thread_id="sess-2")
    print("  status:", r3["status"], "| reply:", r3["reply"])
    print("  profile(跨会话):", svc.profile("u1"))

    line("场景 4：新说法与旧档案冲突 → 检测出来")
    r4 = svc.chat("u1", "我偏好短信沟通", thread_id="sess-3")
    print("  status:", r4["status"])
    if r4["status"] == "pend":
        print("  conflicts:", r4["question"]["conflicts"])
        print("  >>> 旧值=邮件 新值=短信，冲突被检出")

    line("场景 5：人工裁决 keep → 保留旧值")
    if r4["status"] == "pend":
        r5 = svc.approve("sess-3", "keep")
        print("  reply:", r5["reply"])
        print("  profile:", svc.profile("u1"), "  >>> 仍是邮件（旧值保住了）")

    line("场景 6：回放这一轮走过哪些存档点 + 流式输出")
    hist = svc.history("sess-2")
    print(f"  sess-2 存档点数: {len(hist)}")
    for h in hist[:5]:
        print(f"    step={h['step']} next={h['next']}")
    print("\n  流式（sess-stream）:")
    for ev in svc.stream("u1", "买了咖啡", thread_id="sess-stream"):
        if isinstance(ev, dict):
            print("    event:", list(ev.keys())[0])

    line("验收：用户隔离")
    print("  u1 profile:", svc.profile("u1"))
    print("  u9 profile:", svc.profile("u9"), " >>> 别的用户看不到")


if __name__ == "__main__":
    main()
