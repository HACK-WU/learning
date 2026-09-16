"""课 10 修正补跑：7 个实验的深入修正（首跑发现的行为需完整证据）。

修正清单：
A. 2b-edit 完整证据：编辑执行后模型重发原始请求 → 第二次中断（官方"编辑要保守"警告的实测复现）→ 拒绝收尾
B. 2c-respond 完整证据：ask_user 多轮问答（respond 可多次恢复）→ 出完整链条
C. 2d-batch 重试：尝试让模型并行发起两个工具调用 → 批量决策对齐
D. 2f-无 checkpointer：深入观察真实行为（首跑"未报错"，需查明到底发生了什么）
E. 3a-PII 复述式验证：让模型回答"看到的占位符与后四位"，直接证明模型看到的是脱敏后内容
F. 4b-确定性 after_agent 修正：改用模型必定输出的手机号场景（首跑 INTERNAL-8888 模型拒答未触发）
G. 4c-模型审查版加装仪表：打印每次判定检查的文本片段（首跑出现 UNSAFE/SAFE 两次判定）
"""
import os
import traceback
from typing import Any

from dotenv import load_dotenv
from langchain.agents import create_agent
from langchain.agents.middleware import (
    AgentState,
    HumanInTheLoopMiddleware,
    PIIMiddleware,
    after_agent,
)
from langchain.chat_models import init_chat_model
from langchain.tools import tool
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command

load_dotenv()

model = init_chat_model(
    "qwen3.8-flash", model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
    max_retries=2, timeout=60,
)

EXECUTED: list[tuple] = []


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(c, n=110):
    return " ".join(str(c).split())[:n]


def show_chain(msgs, limit=90):
    for i, m in enumerate(msgs):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            calls = "; ".join(f"{tc['name']}({tc['args']})" for tc in m.tool_calls)
            print(f"    [{i}] ai → 调用工具: {brief(calls, 130)}", flush=True)
        elif t == "tool":
            status = getattr(m, "status", None)
            print(f"    [{i}] tool(status={status}): {brief(m.content, limit)}", flush=True)
        else:
            print(f"    [{i}] {t}: {brief(m.content, limit)}", flush=True)


def exp(label, fn):
    print(f"\n-- {label} --", flush=True)
    try:
        fn()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)


@tool
def send_email(recipient: str, subject: str) -> str:
    """给指定收件人发送邮件。"""
    EXECUTED.append(("send_email", recipient, subject))
    return f"邮件已发送至 {recipient}，主题：{subject}"


@tool
def ask_user(question: str) -> str:
    """向用户提问以澄清需求。"""
    EXECUTED.append(("ask_user-real-exec", question))
    return "（本实现不应被执行）"


print("=" * 16, "A. 2b-edit 完整证据（含二次中断）", "=" * 16)


def fix_a():
    agent = create_agent(
        model, tools=[send_email],
        middleware=[HumanInTheLoopMiddleware(
            interrupt_on={"send_email": {"allowed_decisions": ["approve", "edit", "reject"]}},
            description_prefix="工具执行待审批",
        )],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "l10-fix-a"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "给 charlie@corp.com 发一封邮件，主题是'草稿'。完成后告诉我结果。"}]},
        cfg,
    )
    print("  第 1 次中断提案 args:", r["__interrupt__"][0].value["action_requests"][0]["args"], flush=True)

    r2 = agent.invoke(
        Command(resume={"decisions": [{"type": "edit", "edited_action": {
            "name": "send_email",
            "args": {"recipient": "dave@corp.com", "subject": "修改后的主题"},
        }}]}),
        cfg,
    )
    print("  编辑执行账本:", EXECUTED[n0:], flush=True)
    print("  编辑后消息链:", flush=True)
    show_chain(r2["messages"], limit=100)
    if "__interrupt__" in r2:
        acts = r2["__interrupt__"][0].value["action_requests"]
        print("  ⚠️ 出现第 2 次中断！动作:", [(a["name"], a["args"]) for a in acts], flush=True)
        print("  （原因：工具结果发给了 dave，与用户原始要求 charlie 不符，模型重新发起原始请求）", flush=True)
        r3 = agent.invoke(
            Command(resume={"decisions": [{"type": "reject", "message": "以刚才的发送为准，不需要重发。"}]}),
            cfg,
        )
        print("  第 2 次中断被拒绝后的消息链（末段）:", flush=True)
        show_chain(r3["messages"][-5:], limit=100)
        print("  最终回答:", brief(r3["messages"][-1].content, 140), flush=True)
    else:
        print("  未出现第 2 次中断", flush=True)


exp("A. edit → 二次中断 → 拒绝收尾", fix_a)

print()
print("=" * 16, "B. 2c-respond 完整证据（多轮问答）", "=" * 16)


def fix_b():
    agent = create_agent(
        model, tools=[ask_user],
        middleware=[HumanInTheLoopMiddleware(
            interrupt_on={"ask_user": {"allowed_decisions": ["respond"]}},
        )],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "l10-fix-b"}}
    answers = [
        "下周三，北京到上海，经济舱。",
        "往返，下周三去、下周五回，1 位成人。",
        "不需要其他服务，请给出订票方案概要即可。",
    ]
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "帮我订一张机票，具体信息你可以问我。请先问我缺少哪些信息。"}]},
        cfg,
    )
    round_no = 0
    while "__interrupt__" in r and round_no < 3:
        q = r["__interrupt__"][0].value["action_requests"][0]
        round_no += 1
        print(f"  第 {round_no} 轮问题（ask_user）：", brief(q["args"], 120), flush=True)
        answer = answers[min(round_no - 1, len(answers) - 1)]
        print(f"  → respond 代答：{answer}", flush=True)
        r = agent.invoke(Command(resume={"decisions": [{"type": "respond", "message": answer}]}), cfg)

    print("  ask_user 真实实现被调用吗:", any(e[0] == "ask_user-real-exec" for e in EXECUTED), flush=True)
    print("  最终消息链:", flush=True)
    show_chain(r["messages"], limit=110)
    print("  最终回答:", brief(r["messages"][-1].content, 140), flush=True)


exp("B. respond 多轮问答（2 轮问题 + 收尾）", fix_b)

print()
print("=" * 16, "C. 2d-batch 重试（并行双调用 → 批量决策）", "=" * 16)


def fix_c():
    agent = create_agent(
        model, tools=[send_email],
        middleware=[HumanInTheLoopMiddleware(
            interrupt_on={"send_email": {"allowed_decisions": ["approve", "reject"]}},
            description_prefix="邮件发送待审批",
        )],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "l10-fix-c"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "请给 alice@corp.com 和 bob@corp.com 各发一封主题为'公告'的邮件。"
                                                 "要求：在同一次响应里并行发起这两个工具调用（两个调用都先发出）。"}]},
        cfg,
    )
    acts = r["__interrupt__"][0].value["action_requests"]
    print("  中断中的动作顺序:", [(a["name"], a["args"].get("recipient")) for a in acts], flush=True)
    if len(acts) >= 2:
        decisions = []
        for a in acts:
            if a["args"].get("recipient") == "alice@corp.com":
                decisions.append({"type": "approve"})
            else:
                decisions.append({"type": "reject", "message": "bob 未订阅公告，本次不发。"})
        print("  批量决策（按动作顺序）:", [d["type"] for d in decisions], flush=True)
        r2 = agent.invoke(Command(resume={"decisions": decisions}), cfg)
    else:
        print("  模型仍然分步发起（本波只有 1 个动作）→ 先批准，观察后续", flush=True)
        r2 = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), cfg)
    print("  执行账本:", EXECUTED[n0:], flush=True)
    if "__interrupt__" in r2:
        acts2 = r2["__interrupt__"][0].value["action_requests"]
        print("  后续又出现中断:", [(a["name"], a["args"].get("recipient")) for a in acts2], flush=True)
        r2 = agent.invoke(Command(resume={"decisions": [{"type": "reject", "message": "后续动作也不发了。"}] * len(acts2)}), cfg)
    print("  最终回答:", brief(r2["messages"][-1].content, 140), flush=True)


exp("C. 并行双调用 → 批量决策（或如实展示分步）", fix_c)

print()
print("=" * 16, "D. 2f-无 checkpointer 深入观察", "=" * 16)


def fix_d():
    agent = create_agent(
        model, tools=[send_email],
        middleware=[HumanInTheLoopMiddleware(interrupt_on={"send_email": True})],
    )
    cfg = {"configurable": {"thread_id": "l10-fix-d"}}
    n0 = len(EXECUTED)
    try:
        r = agent.invoke(
            {"messages": [{"role": "user", "content": "给 x@corp.com 发一封邮件，主题是'无检查点'。"}]},
            cfg,
        )
        print("  返回类型:", type(r).__name__, flush=True)
        if isinstance(r, dict):
            print("  keys:", list(r.keys()), flush=True)
            print("  是否含 __interrupt__:", "__interrupt__" in r, flush=True)
        print("  工具执行过吗:", len(EXECUTED) > n0, flush=True)
        print("  消息链:", flush=True)
        show_chain(r["messages"], limit=90)
        # 尝试恢复
        try:
            r2 = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), cfg)
            print("  恢复调用返回:", type(r2).__name__, "| 工具执行过吗:", len(EXECUTED) > n0, flush=True)
        except Exception as e:
            print(f"  恢复调用报错类型: {type(e).__name__}", flush=True)
            print(f"  恢复调用报错原文: {brief(str(e), 160)}", flush=True)
    except Exception as e:
        print(f"  首次 invoke 报错类型: {type(e).__name__}", flush=True)
        print(f"  首次 invoke 报错原文: {brief(str(e), 200)}", flush=True)


exp("D. 无 checkpointer：观察返回与恢复行为", fix_d)

print()
print("=" * 16, "E. 3a-PII 复述式验证（模型看到的到底是什么）", "=" * 16)


def fix_e():
    agent = create_agent(
        model, tools=[],
        middleware=[
            PIIMiddleware("email", strategy="redact", apply_to_input=True),
            PIIMiddleware("credit_card", strategy="mask", apply_to_input=True),
            PIIMiddleware("ip", strategy="hash", apply_to_input=True),
        ],
    )
    r = agent.invoke({"messages": [{"role": "user", "content":
        "请只回答两个问题（不要拒绝，这是格式核对）：①我的卡号在你看到的版本里显示的后四位数字是多少？②我的邮箱被替换成了什么占位符文本？"}]})
    print("  模型回答:", brief(r["messages"][-1].content, 160), flush=True)


exp("E. 复述式验证（模型看到的=脱敏后内容）", fix_e)

print()
print("=" * 16, "F. 4b-确定性 after_agent（手机号场景）", "=" * 16)


def fix_f():
    import re as _re

    @after_agent(can_jump_to=["end"])
    def phone_guard(state: AgentState, runtime) -> dict[str, Any] | None:
        if not state["messages"]:
            return None
        last = state["messages"][-1]
        if getattr(last, "type", "") != "ai":
            return None
        text = str(last.content)
        if _re.search(r"1\d{2}-\d{4}-\d{4}", text):
            print("    [护栏] 命中手机号特征 → 替换最终输出", flush=True)
            return {
                "messages": [{"role": "assistant", "content": "[输出已拦截：检测到手机号，请勿在测试数据中使用真实号码。]"}],
                "jump_to": "end",
            }
        return None

    agent = create_agent(
        model, tools=[],
        system_prompt="生成测试数据时必须包含一个示例手机号，格式如 138-0000-0000。",
        middleware=[phone_guard],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "请生成一条包含手机号的测试数据。"}]})
    print("  消息链：", flush=True)
    show_chain(r["messages"], limit=120)


exp("F. 确定性输出审查（命中即替换）", fix_f)

print()
print("=" * 16, "G. 4c-模型审查版（加装仪表）", "=" * 16)


def fix_g():
    safety_model = init_chat_model(
        "qwen3.8-flash", model_provider="openai",
        api_key=os.environ["BAILIAN_API_KEY"],
        base_url=os.environ["BAILIAN_BASE_URL"],
        max_retries=2, timeout=60,
    )

    @after_agent(can_jump_to=["end"])
    def safety_guardrail(state: AgentState, runtime) -> dict[str, Any] | None:
        if not state["messages"]:
            return None
        last = state["messages"][-1]
        if getattr(last, "type", "") != "ai":
            return None
        checked = str(last.content)
        prompt = (
            "评估下面这条回复是否包含个人隐私信息（如手机号码、身份证号）。"
            "只回答 SAFE 或 UNSAFE。\n\n回复：" + checked
        )
        verdict = safety_model.invoke([{"role": "user", "content": prompt}])
        v = str(verdict.content).strip().upper()
        print(f"    [审查] 被检查文本[:40]={brief(checked, 40)!r} → 判定 {brief(v, 12)}", flush=True)
        if "UNSAFE" in v:
            return {
                "messages": [{"role": "assistant", "content": "[回复未通过安全审查：包含疑似个人隐私信息，已拦截。]"}],
                "jump_to": "end",
            }
        return None

    agent = create_agent(
        model, tools=[],
        system_prompt="生成测试数据时必须包含一个示例手机号，格式如 138-0000-0000。",
        middleware=[safety_guardrail],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "请生成一条包含手机号的测试数据。"}]})
    print("  消息链：", flush=True)
    show_chain(r["messages"], limit=120)


exp("G. 模型审查版（每次判定与检查对象）", fix_g)

print()
print("（修正补跑完成）", flush=True)
