"""一键演示：把智能客服的完整能力按场景跑一遍（验收主入口）。

运行：uv run python demo.py

覆盖场景（对应课程知识点见各场景注释）：
1. 政策咨询 → RAG 检索（课 11）
2. 订单 + 物流查询 → 业务工具（课 4）
3. 大额退款 → HITL 人工审批（课 10）
4. 小额退款 → 条件直通（课 10 when 谓词）
5. PII 脱敏 → 手机号打码（课 8 / 10）
6. 多轮记忆 → 同会话上下文（课 7）
7. 转人工 → handoff 最小实现（课 12）
最后：打印审计轨迹（课 8 自定义中间件 / 课 13 可观测性）
"""
import json

from langgraph.types import Command

from app.agent import build_agent
from app.config import UserProfile
from app.middleware.safety import AUDIT_LOG
from app.tools.aftersales import ACTIONS

CUSTOMER = UserProfile(user_id="u-888", name="张女士", member_level="V3")


def banner(text: str) -> None:
    print(f"\n{'=' * 68}\n【{text}】\n{'=' * 68}", flush=True)


def show_trace(messages, answer_limit: int = 220) -> None:
    """打印一次运行的工具调用轨迹与最终回答。"""
    for m in messages:
        mtype = getattr(m, "type", "")
        if mtype == "ai" and getattr(m, "tool_calls", None):
            for tc in m.tool_calls:
                args = json.dumps(tc["args"], ensure_ascii=False)
                print(f"    [工具调用] {tc['name']}({args})", flush=True)
        elif mtype == "tool":
            print(f"    [工具返回] {str(m.content)[:80]}", flush=True)
        elif mtype == "ai" and m.content:
            print(f"    [最终回答] {str(m.content)[:answer_limit]}", flush=True)


def ask(agent, cfg, question: str, context=None) -> dict:
    """发一轮消息（不带审批处理），返回结果。"""
    print(f"  用户: {question}", flush=True)
    result = agent.invoke(
        {"messages": [{"role": "user", "content": question}]},
        cfg,
        context=context or CUSTOMER,
    )
    return result


def main() -> None:
    agent = build_agent()

    # ---- 场景 1：政策咨询（课 11：Agentic RAG——模型自主调用检索工具）----
    banner("场景 1 · 政策咨询（RAG 检索知识库）")
    r = ask(agent, {"configurable": {"thread_id": "demo-1"}},
            "你们支持七天无理由退货吗？我上周买的耳机想退。")
    show_trace(r["messages"])

    # ---- 场景 2：订单 + 物流（课 4：工具组合与多步调用）----
    banner("场景 2 · 订单查询（多步工具调用）")
    r = ask(agent, {"configurable": {"thread_id": "demo-2"}},
            "帮我查一下订单 A1003，到哪了？")
    show_trace(r["messages"])

    # ---- 场景 3：大额退款（课 10：HITL 中断 → 人工审批 → resume）----
    banner("场景 3 · 大额退款（人工审批流程：中断 → 批准 → 执行）")
    cfg3 = {"configurable": {"thread_id": "demo-3"}}
    r = ask(agent, cfg3, "订单 A1001 的智能音箱到货就是坏的，我已经扔了没法寄回，请直接退款 399 元。")
    if "__interrupt__" in r:
        request = r["__interrupt__"][0].value
        for ar in request["action_requests"]:
            print(f"    [审批请求] 操作={ar['name']}｜参数={json.dumps(ar['args'], ensure_ascii=False)}", flush=True)
        print("    [审批人] 核对订单后批准 ✓", flush=True)
        r = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), cfg3, context=CUSTOMER)
        show_trace(r["messages"])
    else:
        print("    （未触发中断——请检查退款金额是否低于审批阈值）", flush=True)

    # ---- 场景 4：小额退款（课 10：when 谓词为 False → 直通）----
    banner("场景 4 · 小额退款（低于阈值：直通、不打扰审批人）")
    r = ask(agent, {"configurable": {"thread_id": "demo-4"}},
            "订单 A1004 的贴膜就 29 块钱，寄回太麻烦了，请直接退款吧。")
    print(f"    是否触发人工审批: {'__interrupt__' in r}（预期 False）", flush=True)
    show_trace(r["messages"])

    # ---- 场景 5：PII 脱敏（课 8/10：手机号进入模型前被打码）----
    banner("场景 5 · PII 脱敏（手机号进模型前自动打码）")
    r = ask(agent, {"configurable": {"thread_id": "demo-5"}},
            "我的手机号是 13812345678，后续有问题请电话联系我。")
    stored = str(r["messages"][0].content)
    print(f"    对话状态中存储的用户消息: {stored}", flush=True)
    print(f"    是否含完整手机号: {'13812345678' in stored}（预期 False——已脱敏）", flush=True)
    show_trace(r["messages"])

    # ---- 场景 6：多轮记忆（课 7：checkpointer 让第二轮记得第一轮）----
    banner("场景 6 · 多轮记忆（同会话，第二轮引用第一轮上下文）")
    cfg6 = {"configurable": {"thread_id": "demo-6"}}
    ask(agent, cfg6, "我在看订单 A1003 这一单。")
    r = ask(agent, cfg6, "它发货了吗？物流到哪了？")
    print(f"    第二轮结束后的会话消息总数: {len(r['messages'])}（跨轮累积——记忆生效）", flush=True)
    show_trace(r["messages"][-4:])

    # ---- 场景 7：转人工（课 12：handoff 概念的最小实现）----
    banner("场景 7 · 转人工（投诉场景升级处理）")
    r = ask(agent, {"configurable": {"thread_id": "demo-7"}},
            "我要投诉！对你们的服务非常不满意，请转人工。")
    show_trace(r["messages"])

    # ---- 收尾：审计轨迹（课 8 自定义中间件 / 课 13 可观测性）----
    banner("审计轨迹（每一次工具调用都被记录）")
    for i, entry in enumerate(AUDIT_LOG, start=1):
        print(
            f"    {i:02d}. {entry['tool']}({json.dumps(entry['args'], ensure_ascii=False)})"
            f"｜耗时 {entry['seconds']}s｜结果: {entry['result'][:60]}",
            flush=True,
        )
    print(f"\n    业务动作账本（真实执行的退货/退款/转人工）: {ACTIONS}", flush=True)
    print("\n演示完成。", flush=True)


if __name__ == "__main__":
    main()
