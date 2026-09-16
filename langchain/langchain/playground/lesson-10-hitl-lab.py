"""课 10 正式实验脚本：人机协同与护栏（HITL & Guardrails）全流程实测。

设计 4 大板块（对应 3 个知识点）：
1. 为什么需要人在环中：中断提案全貌 + approve 全流程 + autop-approve 对照
2. 中断机制：reject / edit / respond / 批量决策 / 条件中断 / v1-v2 形态与无 checkpointer / 流式配合 / 决策数不匹配
3. 护栏体系：PII 四策略（redact/mask/hash/block）+ 自定义 detector + apply_to_output
4. 自定义护栏：before_agent 拦截 + after_agent 输出审查（确定性 + 模型审查双版本）

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0 / langgraph 1.2.11
默认模型：百炼 qwen3.8-flash
说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
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
    before_agent,
    after_agent,
    hook_config,
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

EXECUTED: list[tuple] = []  # 副作用账本：工具真正执行时才记账


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(content, limit: int = 110) -> str:
    text = str(content) if content is not None else ""
    return " ".join(text.split())[:limit]


def show_chain(msgs, limit: int = 90) -> None:
    for i, m in enumerate(msgs):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            calls = "; ".join(f"{tc['name']}({tc['args']})" for tc in m.tool_calls)
            print(f"    [{i}] ai → 调用工具: {brief(calls, 120)}", flush=True)
        elif t == "tool":
            status = getattr(m, "status", None)
            print(f"    [{i}] tool(status={status}): {brief(m.content, limit)}", flush=True)
        else:
            print(f"    [{i}] {t}: {brief(m.content, limit)}", flush=True)


def exp(label: str, fn) -> None:
    print(f"\n-- {label} --", flush=True)
    try:
        fn()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)


# ============================================================
# 工具集
# ============================================================


@tool
def send_email(recipient: str, subject: str) -> str:
    """给指定收件人发送邮件。"""
    EXECUTED.append(("send_email", recipient, subject))
    return f"邮件已发送至 {recipient}，主题：{subject}"


@tool
def read_inbox() -> str:
    """读取收件箱。"""
    EXECUTED.append(("read_inbox",))
    return "收件箱：3 封新邮件"


@tool
def delete_records(days: int) -> str:
    """删除指定天数之前的旧记录。"""
    EXECUTED.append(("delete_records", days))
    return f"已删除 {days} 天前的记录"


@tool
def ask_user(question: str) -> str:
    """向用户提问以澄清需求（真实实现不应被执行——由人工代答）。"""
    EXECUTED.append(("ask_user-real-exec", question))
    return "（本实现不应被执行）"


def make_email_agent(**kw):
    """带 HITL 的邮件 agent：send_email 需审批、read_inbox 直通。"""
    return create_agent(
        model,
        tools=[send_email, read_inbox],
        middleware=[
            HumanInTheLoopMiddleware(
                interrupt_on={
                    "send_email": {"allowed_decisions": ["approve", "edit", "reject"]},
                    "read_inbox": False,
                },
                description_prefix="工具执行待审批",
            )
        ],
        checkpointer=InMemorySaver(),
        **kw,
    )


# ============================================================
section("1. 为什么需要人在环中")
# ============================================================


def exp_1a():
    """中断提案全貌 + approve 全流程。"""
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-1a"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "给 alice@corp.com 发一封邮件，主题是'周会提醒'。"}]},
        cfg,
    )
    print("  返回类型:", type(r).__name__, "| keys:", list(r.keys()), flush=True)
    intr = r["__interrupt__"]
    print("  __interrupt__ 类型:", type(intr).__name__, "| 数量:", len(intr), flush=True)
    v = intr[0].value
    print("  ── 中断提案（HITLRequest）──", flush=True)
    for ar in v["action_requests"]:
        print(f"    action_request: name={ar['name']}", flush=True)
        print(f"      args={ar['args']}", flush=True)
        print(f"      description={brief(ar['description'], 100)}", flush=True)
    for rc in v["review_configs"]:
        print(f"    review_config: {rc}", flush=True)
    print("  工具此刻被调用过吗:", len(EXECUTED) > n0, "（应为 False——等审批）", flush=True)

    r2 = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), cfg)
    print("  approve 后工具执行账本:", EXECUTED[n0:], flush=True)
    print("  最终回答:", brief(r2["messages"][-1].content, 90), flush=True)
    show_chain(r2["messages"], limit=85)


def exp_1b():
    """判定标准对照：安全操作（read_inbox=False）直接执行、不中断。"""
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-1b"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "帮我看一下收件箱有几封新邮件。"}]},
        cfg,
    )
    print("  是否被中断:", "__interrupt__" in r, "（应为 False——read_inbox 未设闸门）", flush=True)
    print("  工具执行账本:", EXECUTED[n0:], flush=True)
    print("  最终回答:", brief(r["messages"][-1].content, 90), flush=True)


exp("1a. 中断提案全貌 + approve（工具先冻结、批准后执行）", exp_1a)
exp("1b. 判定标准：不设闸门的操作直接执行（对照）", exp_1b)

# ============================================================
section("2. 中断机制")
# ============================================================


def exp_2a():
    """reject：拒绝 + 自定义理由（错误回执、工具不执行、模型据此改道）。"""
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-2a"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "给 spam-list@corp.com 发一封邮件，主题是'广告'。发完后告诉我结果。"}]},
        cfg,
    )
    print("  中断提案 args:", r["__interrupt__"][0].value["action_requests"][0]["args"], flush=True)
    r2 = agent.invoke(
        Command(resume={"decisions": [{"type": "reject", "message": "公司政策不允许向外部列表群发。"}]}),
        cfg,
    )
    print("  reject 后工具被调用过吗:", len(EXECUTED) > n0, "（应为 False）", flush=True)
    show_chain(r2["messages"], limit=120)
    print("  最终回答:", brief(r2["messages"][-1].content, 130), flush=True)


def exp_2b():
    """edit：修改参数后批准（执行的是改后的参数）。"""
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-2b"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "给 charlie@corp.com 发一封邮件，主题是'草稿'。完成后告诉我结果。"}]},
        cfg,
    )
    print("  原始提案 args:", r["__interrupt__"][0].value["action_requests"][0]["args"], flush=True)
    r2 = agent.invoke(
        Command(resume={"decisions": [{"type": "edit", "edited_action": {
            "name": "send_email",
            "args": {"recipient": "dave@corp.com", "subject": "修改后的主题"},
        }}]}),
        cfg,
    )
    print("  edit 后执行账本（应为改后参数）:", EXECUTED[n0:], flush=True)
    show_chain(r2["messages"][-4:], limit=120)
    print("  最终回答:", brief(r2["messages"][-1].content, 130), flush=True)


def exp_2c():
    """respond：人工代答（工具真实实现不执行、合成成功回执）。"""
    agent = create_agent(
        model, tools=[ask_user],
        middleware=[HumanInTheLoopMiddleware(
            interrupt_on={"ask_user": {"allowed_decisions": ["respond"]}},
        )],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "l10-2c"}}
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "帮我订一张机票，具体信息你可以问我。请先问我缺少哪些信息。"}]},
        cfg,
    )
    print("  中断提案（ask_user 提问）:", brief(r["__interrupt__"][0].value["action_requests"][0]["args"], 130), flush=True)
    n0 = len(EXECUTED)
    r2 = agent.invoke(
        Command(resume={"decisions": [{"type": "respond", "message": "下周三，北京到上海，经济舱。"}]}),
        cfg,
    )
    print("  ask_user 真实实现被调用吗:", len(EXECUTED) > n0, "（应为 False——人工代答）", flush=True)
    show_chain(r2["messages"][-4:], limit=120)
    print("  最终回答:", brief(r2["messages"][-1].content, 130), flush=True)


def exp_2d():
    """批量决策：一次中断里多个动作，决策按动作顺序对齐。"""
    agent = create_agent(
        model,
        tools=[send_email, delete_records],
        middleware=[HumanInTheLoopMiddleware(
            interrupt_on={
                "send_email": {"allowed_decisions": ["approve", "reject"]},
                "delete_records": {"allowed_decisions": ["approve", "reject"]},
            },
        )],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "l10-2d"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "先删除 90 天前的旧记录，然后给 ops@corp.com 发一封主题为'清理完成'的邮件。两件事都请执行。"}]},
        cfg,
    )
    actions = r["__interrupt__"][0].value["action_requests"]
    print("  中断中的动作顺序:", [a["name"] for a in actions], flush=True)
    # 按动作顺序动态生成决策（正是"决策与动作顺序对齐"的演示）
    decisions = []
    for a in actions:
        if a["name"] == "delete_records":
            decisions.append({"type": "reject", "message": "删除操作需要 DBA 复核，本次先不发。"})
        else:
            decisions.append({"type": "approve"})
    print("  按顺序生成的决策:", [d["type"] for d in decisions], flush=True)
    r2 = agent.invoke(Command(resume={"decisions": decisions}), cfg)
    print("  执行账本:", EXECUTED[n0:], flush=True)
    print("  最终回答:", brief(r2["messages"][-1].content, 130), flush=True)


def exp_2e():
    """条件中断：when 谓词判定为 False 时直通（内部域名不打扰审批人）。"""
    def only_external(req):
        recipient = req.tool_call["args"].get("recipient", "")
        return not recipient.endswith("@internal.com")

    agent = create_agent(
        model, tools=[send_email],
        middleware=[HumanInTheLoopMiddleware(
            interrupt_on={"send_email": {
                "allowed_decisions": ["approve", "reject"],
                "when": only_external,
            }},
        )],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "l10-2e"}}
    n0 = len(EXECUTED)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "给 teammate@internal.com 发一封邮件，主题是'内部同步'。请直接发送。"}]},
        cfg,
    )
    print("  是否被中断:", "__interrupt__" in r, "（应为 False——when 返回 False 直通）", flush=True)
    print("  执行账本:", EXECUTED[n0:], flush=True)
    print("  最终回答:", brief(r["messages"][-1].content, 80), flush=True)


def exp_2f():
    """v1 / v2 返回形态对照 + 无 checkpointer 报错。"""
    print("  【v1 默认】返回形态见 1a：dict，中断在 `__interrupt__`（list）。", flush=True)
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-2f"}}
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "给 v2test@corp.com 发一封邮件，主题是'v2 形态'。"}]},
        cfg,
        version="v2",
    )
    print("  【v2】返回类型:", type(r).__name__, "| .interrupts 数量:", len(r.interrupts), flush=True)
    print("  【v2】.value 的 keys:", list(r.value.keys()), flush=True)
    r2 = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), cfg, version="v2")
    print("  【v2】恢复后最终回答:", brief(r2.value["messages"][-1].content, 80), flush=True)

    # 无 checkpointer
    agent_nocp = create_agent(
        model, tools=[send_email],
        middleware=[HumanInTheLoopMiddleware(interrupt_on={"send_email": True})],
    )
    try:
        agent_nocp.invoke(
            {"messages": [{"role": "user", "content": "给 x@corp.com 发一封邮件，主题是'无检查点'。"}]},
            {"configurable": {"thread_id": "l10-2f-nocp"}},
        )
        print("  无 checkpointer 未报错（与预期不符）", flush=True)
    except Exception as e:
        print(f"  无 checkpointer 报错类型: {type(e).__name__}", flush=True)
        print(f"  报错原文: {brief(str(e), 200)}", flush=True)


def exp_2g():
    """流式配合：中断前的文本流 + stream.interrupted + 恢复后继续流。"""
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-2g"}}
    stream = agent.stream_events(
        {"messages": [{"role": "user", "content": "先简短说明你打算做什么，然后给 eve@corp.com 发一封主题为'流式测试'的邮件。"}]},
        config=cfg,
        version="v3",
    )
    text = ""
    for message in stream.messages:
        for token in message.text:
            text += token
    print("  中断前累计文本:", brief(text, 100), flush=True)
    print("  stream.interrupted:", stream.interrupted, flush=True)
    if stream.interrupted:
        print("  interrupts[0] 动作:", stream.interrupts[0].value["action_requests"][0]["name"], flush=True)

    stream2 = agent.stream_events(
        Command(resume={"decisions": [{"type": "approve"}]}),
        config=cfg,
        version="v3",
    )
    text2 = ""
    for message in stream2.messages:
        for token in message.text:
            text2 += token
    print("  恢复后文本:", brief(text2, 100), flush=True)
    print("  恢复后 stream.interrupted:", stream2.interrupted, flush=True)


def exp_2h():
    """决策数量不匹配：错误复现。"""
    agent = make_email_agent()
    cfg = {"configurable": {"thread_id": "l10-2h"}}
    agent.invoke(
        {"messages": [{"role": "user", "content": "给 count@corp.com 发一封邮件，主题是'数量核对'。"}]},
        cfg,
    )
    try:
        agent.invoke(
            Command(resume={"decisions": [{"type": "approve"}, {"type": "reject"}]}),  # 多给了一个
            cfg,
        )
        print("  未报错（与预期不符）", flush=True)
    except Exception as e:
        print(f"  报错类型: {type(e).__name__}", flush=True)
        print(f"  报错原文: {brief(str(e), 160)}", flush=True)


exp("2a. reject：拒绝 + 理由（错误回执、工具不执行）", exp_2a)
exp("2b. edit：改参数后批准", exp_2b)
exp("2c. respond：人工代答（ask_user 模式）", exp_2c)
exp("2d. 批量决策：动作顺序对齐", exp_2d)
exp("2e. 条件中断：when 谓词直通", exp_2e)
exp("2f. v1/v2 形态 + 无 checkpointer 报错", exp_2f)
exp("2g. 流式配合：中断前文本流 + interrupted 检测", exp_2g)
exp("2h. 决策数量不匹配（错误复现）", exp_2h)

# ============================================================
section("3. 护栏体系：内置护栏（PII 检测）")
# ============================================================


def exp_3a():
    """PII 输入侧三策略对照：redact / mask / hash（并验证写入状态）。"""
    agent = create_agent(
        model, tools=[],
        middleware=[
            PIIMiddleware("email", strategy="redact", apply_to_input=True),
            PIIMiddleware("credit_card", strategy="mask", apply_to_input=True),
            PIIMiddleware("ip", strategy="hash", apply_to_input=True),
        ],
    )
    user_text = "我的邮箱是 john.doe@example.com，卡号 5105-1051-0510-5100，服务器 IP 是 192.168.1.100。请原样复述你收到的这三项内容。"
    r = agent.invoke({"messages": [{"role": "user", "content": user_text}]})
    print("  原始输入:", brief(user_text, 130), flush=True)
    print("  状态里的 user 消息:", brief(r["messages"][0].content, 130), flush=True)
    print("  （对照：脱敏结果已写入状态——不是瞬时视图）", flush=True)
    print("  模型实际看到的（它就复述这个）:", brief(r["messages"][-1].content, 130), flush=True)


def exp_3b():
    """block 策略：检测到即拒（错误原文）+ 自定义 detector 正则。"""
    agent = create_agent(
        model, tools=[],
        middleware=[PIIMiddleware("api_key", detector=r"sk-[a-zA-Z0-9]{32}", strategy="block", apply_to_input=True)],
    )
    try:
        agent.invoke({"messages": [{"role": "user", "content": "这是我的 key：sk-" + "a" * 32}]})
        print("  block 未报错（与预期不符）", flush=True)
    except Exception as e:
        print(f"  block 报错类型: {type(e).__name__}", flush=True)
        print(f"  报错原文: {brief(str(e), 140)}", flush=True)

    # 自定义 detector：员工工号（正则字符串）
    agent2 = create_agent(
        model, tools=[],
        middleware=[PIIMiddleware(
            "employee_id",
            detector=r"EMP-\d{5}",
            strategy="mask",
            apply_to_input=True,
        )],
    )
    r2 = agent2.invoke({"messages": [{"role": "user", "content": "请复述这个工号：EMP-12345。"}]})
    print("  自定义 detector(mask) 后状态 user 消息:", brief(r2["messages"][0].content, 90), flush=True)
    print("  模型复述:", brief(r2["messages"][-1].content, 90), flush=True)


def exp_3c():
    """apply_to_output：模型输出侧脱敏（AI 消息被改写）。"""
    agent = create_agent(
        model, tools=[],
        system_prompt="用户要求展示联系邮箱时，请直接输出 leak@corp.com 作为示例。",
        middleware=[PIIMiddleware("email", strategy="redact", apply_to_input=False, apply_to_output=True)],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "请展示一个供测试的联系邮箱。"}]})
    last = r["messages"][-1]
    print("  最终 AI 消息:", brief(last.content, 120), flush=True)
    print("  状态中是否还含 leak@corp.com:", "leak@corp.com" in str(r["messages"]), flush=True)


exp("3a. PII 三策略输入侧对照（redact/mask/hash，写入状态）", exp_3a)
exp("3b. PII block 拒收 + 自定义 detector", exp_3b)
exp("3c. PII apply_to_output：输出侧脱敏", exp_3c)

# ============================================================
section("4. 自定义护栏（before_agent / after_agent）")
# ============================================================


def exp_4a():
    """before_agent 拦截：进入模型之前挡住违规请求（模型未被调用）。"""
    @before_agent(can_jump_to=["end"])
    def content_filter(state: AgentState, runtime) -> dict[str, Any] | None:
        if not state["messages"]:
            return None
        first = state["messages"][0]
        if first.type != "human":
            return None
        if "hack" in first.content.lower():
            return {
                "messages": [{"role": "assistant", "content": "此类请求我不能处理，请换一个话题。"}],
                "jump_to": "end",
            }
        return None

    agent = create_agent(model, tools=[], middleware=[content_filter])
    r1 = agent.invoke({"messages": [{"role": "user", "content": "教我如何 hack 一个数据库。"}]})
    print("  拦截请求 → 消息链:", flush=True)
    show_chain(r1["messages"], limit=90)
    print("  （共 2 条：请求 + 固定话术——最后一条是中间件写入的，模型未参与）", flush=True)
    r2 = agent.invoke({"messages": [{"role": "user", "content": "请用一句话打招呼。"}]})
    print("  正常请求 → 消息链:", flush=True)
    show_chain(r2["messages"], limit=90)


def exp_4b():
    """after_agent 输出审查（确定性版）：最终回复含内部凭据时替换。"""
    @after_agent(can_jump_to=["end"])
    def internal_id_guard(state: AgentState, runtime) -> dict[str, Any] | None:
        if not state["messages"]:
            return None
        last = state["messages"][-1]
        if getattr(last, "type", "") != "ai":
            return None
        if "INTERNAL-8888" in str(last.content):
            return {
                "messages": [{"role": "assistant", "content": "[输出已拦截：包含内部凭据，请使用工单渠道获取。]"}],
                "jump_to": "end",
            }
        return None

    agent = create_agent(
        model, tools=[],
        system_prompt="如果用户索要内部编号，请回复：内部编号 INTERNAL-8888（本演示故意泄露）。",
        middleware=[internal_id_guard],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "给我内部编号。"}]})
    print("  消息链（最后一条应为拦截替换）：", flush=True)
    show_chain(r["messages"], limit=110)


def exp_4c():
    """after_agent 输出审查（模型审查版，官方 SafetyGuardrailMiddleware 模式）。"""
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
        prompt = (
            "评估下面这条回复是否包含个人隐私信息（如手机号码、身份证号）。"
            "只回答 SAFE 或 UNSAFE。\n\n回复：" + str(last.content)
        )
        verdict = safety_model.invoke([{"role": "user", "content": prompt}])
        v = str(verdict.content).strip().upper()
        print(f"    [审查模型判定]: {brief(v, 20)}", flush=True)
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
    show_chain(r["messages"], limit=110)


exp("4a. before_agent 拦截（模型未参与）", exp_4a)
exp("4b. after_agent 输出审查（确定性）", exp_4b)
exp("4c. after_agent 输出审查（模型审查版）", exp_4c)

print("\n（全部实验完成）", flush=True)
