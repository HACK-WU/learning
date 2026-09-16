"""课 9 正式实验脚本：Context Engineering 上下文工程（全流程实测）。

设计 4 大板块（对应 3 个知识点）：
1. 上下文工程是什么：组装视图（模型看到什么）+ 成本对照（上下文窗口=稀缺资源）
2. 模型上下文：动态提示词（状态/运行时）× 消息注入（瞬时 vs 持久）× 动态工具 × 动态格式 × 工具结果清理（瞬时截断 vs ContextEditing）
3. 工具上下文：工具读运行时上下文 / 读写状态（Command）/ 写 store（跨会话）
4. 生命周期上下文：摘要的持久更新 + 自定义审计钩子（状态计数 + store 沉淀）

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0 / langgraph 1.2.11
默认模型：百炼 qwen3.8-flash（结构化输出段用关闭思考模式的同款）
说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import os
import traceback
from dataclasses import dataclass
from typing import Callable

from dotenv import load_dotenv
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import (
    AgentMiddleware,
    ContextEditingMiddleware,
    ClearToolUsesEdit,
    ExtendedModelResponse,
    ModelRequest,
    SummarizationMiddleware,
    dynamic_prompt,
    wrap_model_call,
)
from langchain.agents.structured_output import ToolStrategy
from langchain.chat_models import init_chat_model
from langchain.messages import HumanMessage, ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
from pydantic import BaseModel, Field
from typing_extensions import NotRequired

load_dotenv()

API_KEY = os.environ["BAILIAN_API_KEY"]
BASE_URL = os.environ["BAILIAN_BASE_URL"]


def make_model(**kw):
    return init_chat_model(
        "qwen3.8-flash", model_provider="openai",
        api_key=API_KEY, base_url=BASE_URL, max_retries=2, timeout=60, **kw,
    )


model = make_model()
model_no_think = make_model(extra_body={"enable_thinking": False})


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(content, limit: int = 110) -> str:
    text = str(content) if content is not None else ""
    return " ".join(text.split())[:limit]


def show_chain(msgs, limit: int = 80) -> None:
    for i, m in enumerate(msgs):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            calls = "; ".join(f"{tc['name']}({tc['args']})" for tc in m.tool_calls)
            print(f"    [{i}] ai → 调用工具: {calls}", flush=True)
        else:
            print(f"    [{i}] {t}: {brief(m.content, limit)}", flush=True)


def exp(label: str, fn) -> None:
    print(f"\n-- {label} --", flush=True)
    try:
        fn()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
        traceback.print_exc()


# ============================================================
section("1. 上下文工程是什么")
# ============================================================


def exp_1a():
    """组装视图：一次模型调用实际看到的上下文要素。"""

    @wrap_model_call
    def show_context(request: ModelRequest, handler):
        sys_text = str(request.system_message.content) if request.system_message else "(无)"
        print(f"  [组装视图] system prompt: {brief(sys_text, 90)}", flush=True)
        print(f"  [组装视图] 消息 {len(request.messages)} 条: "
              f"{[getattr(m, 'type', '?') for m in request.messages]}", flush=True)
        tools = request.tools or []
        print(f"  [组装视图] 工具 {len(tools)} 个: {[getattr(t, 'name', '?') for t in tools]}", flush=True)
        print(f"  [组装视图] 模型: {getattr(request.model, 'model_name', type(request.model).__name__)}", flush=True)
        return handler(request)

    @tool
    def get_weather(city: str) -> str:
        """查询一个城市的天气。"""
        return f"{city}：晴天，22°C"

    agent = create_agent(
        model, tools=[get_weather],
        system_prompt="你是一个天气助手，回答保持简短。",
        middleware=[show_context],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "北京天气怎么样？"}]})
    print("  最终回答:", brief(r["messages"][-1].content), flush=True)


def exp_1b():
    """成本对照：同一问题，短 system prompt vs 塞满参考资料的 system prompt。"""
    ref = "【参考资料】" + (
        "该项目采用微服务架构，订单服务负责交易流程，库存服务负责货品管理，"
        "用户服务负责账号体系，各服务之间通过消息队列通信。" * 30
    )
    print(f"  （长提示词参考资料共 {len(ref)} 字）", flush=True)

    @tool
    def noop() -> str:
        """占位工具。"""
        return "ok"

    agent_short = create_agent(
        model, tools=[], system_prompt="你是一个简洁的助手。",
    )
    r1 = agent_short.invoke({"messages": [{"role": "user", "content": "请只回答数字：1+1 等于几？"}]})
    u1 = r1["messages"][-1].usage_metadata or {}
    print(f"  短提示词（{len('你是一个简洁的助手。')} 字）: "
          f"input_tokens = {u1.get('input_tokens')}, 总 tokens = {u1.get('total_tokens')}", flush=True)

    agent_long = create_agent(
        model, tools=[], system_prompt="你是一个简洁的助手。\n" + ref,
    )
    r2 = agent_long.invoke({"messages": [{"role": "user", "content": "请只回答数字：1+1 等于几？"}]})
    u2 = r2["messages"][-1].usage_metadata or {}
    print(f"  长提示词（共 {len(ref) + 9} 字）: "
          f"input_tokens = {u2.get('input_tokens')}, 总 tokens = {u2.get('total_tokens')}", flush=True)
    delta = (u2.get("input_tokens") or 0) - (u1.get("input_tokens") or 0)
    print(f"  差额: 多携带 {delta} tokens（每次调用都要重复付这笔账）", flush=True)


exp("1a. 组装视图：模型一次调用看到什么", exp_1a)
exp("1b. 成本对照：上下文窗口是稀缺资源", exp_1b)

# ============================================================
section("2. 模型上下文")
# ============================================================


def exp_2a():
    """dynamic_prompt 按状态定制：长对话 → 简洁模式。"""

    @dynamic_prompt
    def state_aware(request: ModelRequest) -> str:
        base = "你是一个助手。"
        if len(request.messages) >= 5:
            base += "\n这是长对话，请格外简洁。"
        return base

    @wrap_model_call
    def probe(request: ModelRequest, handler):
        print(f"  [探针] 消息 {len(request.messages)} 条 → system: "
              f"{brief(str(request.system_message.content), 70)}", flush=True)
        return handler(request)

    agent = create_agent(model, tools=[], middleware=[state_aware, probe])

    print("  场景一（短对话，1 条消息）:", flush=True)
    r1 = agent.invoke({"messages": [{"role": "user", "content": "用一句话说你好。"}]})
    print("  回答:", brief(r1["messages"][-1].content, 80), flush=True)

    print("  场景二（长对话，共 5 条消息）:", flush=True)
    history = []
    for i in range(2):
        history.append({"role": "user", "content": f"第{i + 1}问：二加二等于几？"})
        history.append({"role": "assistant", "content": "等于四。"})
    history.append({"role": "user", "content": "第 3 问：三加三等于几？"})
    r2 = agent.invoke({"messages": history})
    print("  回答:", brief(r2["messages"][-1].content, 80), flush=True)


def exp_2b():
    """dynamic_prompt 按运行时上下文定制：admin vs viewer。"""

    @dataclass
    class RoleCtx:
        role: str

    @dynamic_prompt
    def role_prompt(request: ModelRequest) -> str:
        role = request.runtime.context.role
        base = "你是一个数据管理助手。"
        if role == "admin":
            base += "\n当前用户是管理员，拥有全部操作权限。"
        else:
            base += "\n当前用户是只读访客，只能执行读取操作，不能修改数据。"
        return base

    @wrap_model_call
    def probe(request: ModelRequest, handler):
        print(f"  [探针·{request.runtime.context.role}] system: "
              f"{brief(str(request.system_message.content), 90)}", flush=True)
        return handler(request)

    agent = create_agent(
        model, tools=[], middleware=[role_prompt, probe], context_schema=RoleCtx,
    )
    print("  admin 用户:", flush=True)
    r1 = agent.invoke({"messages": [{"role": "user", "content": "你可以执行哪些操作？一句话回答。"}]},
                      context=RoleCtx(role="admin"))
    print("  回答:", brief(r1["messages"][-1].content, 90), flush=True)
    print("  viewer 用户:", flush=True)
    r2 = agent.invoke({"messages": [{"role": "user", "content": "你可以执行哪些操作？一句话回答。"}]},
                      context=RoleCtx(role="viewer"))
    print("  回答:", brief(r2["messages"][-1].content, 90), flush=True)


def exp_2c():
    """消息：瞬时注入（transient）——模型看得到，状态里没有。"""

    @wrap_model_call
    def inject_transient(request: ModelRequest, handler):
        msgs = [*request.messages, HumanMessage("[档案注入] 项目代号是 LYRA-9。")]
        return handler(request.override(messages=msgs))

    agent = create_agent(model, tools=[], middleware=[inject_transient],
                         checkpointer=InMemorySaver())
    cfg = {"configurable": {"thread_id": "ctx-transient"}}
    r = agent.invoke({"messages": [{"role": "user", "content": "项目代号是什么？请直接回答。"}]}, cfg)
    print("  回答:", brief(r["messages"][-1].content, 90), flush=True)
    print("  状态里的消息链:", flush=True)
    show_chain(r["messages"])
    persisted = [m for m in r["messages"] if "[档案注入]" in str(getattr(m, "content", ""))]
    print(f"  状态中包含注入标记『[档案注入]』的消息数: {len(persisted)}（应为 0——瞬时修改不写状态）", flush=True)


def exp_2d():
    """消息：持久注入（persistent）——Command 写入状态，跨轮可见。"""

    @wrap_model_call
    def persist_note(request: ModelRequest, handler):
        already = any("LYRA-9" in str(getattr(m, "content", "")) for m in request.messages)
        if already:
            print("  [档案] 已在消息中，本次不再注入", flush=True)
            return handler(request)
        # 本轮：临时带上档案（让本轮就能用）
        msgs = [*request.messages, HumanMessage("[档案] 项目代号是 LYRA-9。")]
        response = handler(request.override(messages=msgs))
        # 未来：把档案持久写入状态
        print("  [档案] 本轮临时注入给模型 + 持久写入状态留给未来轮次", flush=True)
        return ExtendedModelResponse(
            model_response=response,
            command=Command(update={"messages": [HumanMessage("[档案] 项目代号是 LYRA-9。")]}),
        )

    agent = create_agent(model, tools=[], middleware=[persist_note],
                         checkpointer=InMemorySaver())
    cfg = {"configurable": {"thread_id": "ctx-persist"}}
    r1 = agent.invoke({"messages": [{"role": "user", "content": "项目代号是什么？请直接回答。"}]}, cfg)
    last_ai = next((m for m in reversed(r1["messages"]) if getattr(m, "type", "") == "ai"), None)
    print("  第一轮回答:", brief(last_ai.content if last_ai else "", 90), flush=True)
    persisted = [m for m in r1["messages"] if "[档案]" in str(getattr(m, "content", ""))]
    print(f"  第一轮后状态中包含注入标记『[档案]』的消息数: {len(persisted)}（应为 1——持久写入）", flush=True)
    print("  状态链:", flush=True)
    show_chain(r1["messages"])

    r2 = agent.invoke({"messages": [{"role": "user", "content": "再说一次：项目代号是什么？"}]}, cfg)
    last_ai2 = next((m for m in reversed(r2["messages"]) if getattr(m, "type", "") == "ai"), None)
    print("  第二轮回答（无任何注入，直接读状态）:", brief(last_ai2.content if last_ai2 else "", 90), flush=True)
    persisted2 = [m for m in r2["messages"] if "[档案]" in str(getattr(m, "content", ""))]
    print(f"  第二轮后『[档案]』消息数: {len(persisted2)}（不重复注入，仍为 1）", flush=True)


def exp_2e():
    """工具：按运行时角色动态选择。"""

    @dataclass
    class RoleCtx:
        role: str

    @tool
    def read_data() -> str:
        """读取业务数据。"""
        return "数据内容：42"

    @tool
    def write_data(text: str) -> str:
        """写入业务数据。"""
        return f"已写入：{text}"

    @tool
    def delete_data() -> str:
        """删除全部业务数据。"""
        return "已删除全部业务数据"

    @wrap_model_call
    def role_tools(request: ModelRequest, handler):
        role = request.runtime.context.role
        tools = list(request.tools or [])
        if role == "viewer":
            tools = [t for t in tools if t.name.startswith("read_")]
        print(f"  [过滤·{role}] 模型可见工具: {[t.name for t in tools]}", flush=True)
        return handler(request.override(tools=tools))

    agent = create_agent(
        model, tools=[read_data, write_data, delete_data],
        middleware=[role_tools], context_schema=RoleCtx,
    )
    print("  viewer（只读）用户提问『请删除所有业务数据』:", flush=True)
    r1 = agent.invoke({"messages": [{"role": "user", "content": "请删除所有业务数据。"}]},
                      context=RoleCtx(role="viewer"))
    print("  回答:", brief(r1["messages"][-1].content, 130), flush=True)
    print("  admin 用户提问『请读取业务数据』:", flush=True)
    r2 = agent.invoke({"messages": [{"role": "user", "content": "请读取业务数据。"}]},
                      context=RoleCtx(role="admin"))
    print("  回答:", brief(r2["messages"][-1].content, 130), flush=True)


def exp_2f():
    """格式：动态 response_format（创建时声明候选，中间件收窄）。"""

    class Simple(BaseModel):
        """简单回答。"""
        answer: str = Field(description="简短回答")

    class Detailed(BaseModel):
        """详细回答。"""
        answer: str = Field(description="详细回答")
        confidence: float = Field(description="置信度 0-1")

    @wrap_model_call
    def state_based_format(request: ModelRequest, handler):
        n = len(request.messages)
        if n <= 2:
            fmt = ToolStrategy(Simple)
            print(f"  [格式] 消息 {n} 条 → 简单格式 Simple", flush=True)
        else:
            fmt = ToolStrategy(Detailed)
            print(f"  [格式] 消息 {n} 条 → 详细格式 Detailed", flush=True)
        return handler(request.override(response_format=fmt))

    agent = create_agent(
        model_no_think, tools=[], middleware=[state_based_format],
        response_format=ToolStrategy(Simple | Detailed),
    )
    r1 = agent.invoke({"messages": [{"role": "user", "content": "说一声你好。"}]})
    sr1 = r1.get("structured_response")
    print(f"  第一轮 structured_response: {sr1} | type: {type(sr1).__name__}", flush=True)

    history = [
        {"role": "user", "content": "你好。"},
        {"role": "assistant", "content": "你好！"},
        {"role": "user", "content": "今天星期几？"},
        {"role": "assistant", "content": "抱歉，我无法得知当前日期。"},
        {"role": "user", "content": "那简单介绍一下你自己，并给出你对回答的置信度。"},
    ]
    r2 = agent.invoke({"messages": history})
    sr2 = r2.get("structured_response")
    print(f"  第二轮 structured_response: {sr2} | type: {type(sr2).__name__}", flush=True)


@tool
def big_report(topic: str) -> str:
    """获取主题报告全文。"""
    return "【报告】" + ("这是一条很长的报告内容，包含许多细节。" * 60)


class ToolLenProbe(AgentMiddleware):
    """打印工具消息在两个世界的长度。"""

    def wrap_model_call(self, request: ModelRequest, handler: Callable):
        for m in request.messages:
            if getattr(m, "type", "") == "tool":
                meta = getattr(m, "response_metadata", {})
                cleared = meta.get("context_editing", {}).get("cleared")
                print(f"  [探针] 模型侧 tool 消息: len={len(str(m.content))} "
                      f"cleared={cleared} content[:46]={str(m.content)[:46]!r}", flush=True)
        return handler(request)


def exp_2g_transient():
    """工具结果清理 A：自写瞬时截断（模型看短版，状态留全量）。"""

    class TrimLongToolOutputs(AgentMiddleware):
        def wrap_model_call(self, request: ModelRequest, handler: Callable):
            new_msgs = []
            for m in request.messages:
                if getattr(m, "type", "") == "tool" and len(str(m.content)) > 120:
                    m = m.model_copy(update={"content": str(m.content)[:120] + "……（已截断）"})
                new_msgs.append(m)
            return handler(request.override(messages=new_msgs))

    agent = create_agent(
        model, tools=[big_report],
        middleware=[TrimLongToolOutputs(), ToolLenProbe()],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "请获取主题报告，然后只回我'已阅'两个字。"}]})
    print("  最终回答:", brief(r["messages"][-1].content, 60), flush=True)
    for m in r["messages"]:
        if getattr(m, "type", "") == "tool":
            print(f"  状态侧 tool 消息: len={len(str(m.content))}（全量保留）", flush=True)


def exp_2g_editing():
    """工具结果清理 B：内置 ContextEditingMiddleware（同样是瞬时清理）。"""
    agent = create_agent(
        model, tools=[big_report],
        middleware=[
            ContextEditingMiddleware(edits=[ClearToolUsesEdit(trigger=100, keep=0)]),
            ToolLenProbe(),
        ],
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "请获取主题报告，然后只回我'已阅'两个字。"}]})
    print("  最终回答:", brief(r["messages"][-1].content, 60), flush=True)
    for m in r["messages"]:
        if getattr(m, "type", "") == "tool":
            print(f"  状态侧 tool 消息: len={len(str(m.content))}（内置件也是瞬时——状态保留原文）", flush=True)


exp("2a. dynamic_prompt 按状态定制", exp_2a)
exp("2b. dynamic_prompt 按运行时上下文定制", exp_2b)
exp("2c. 消息瞬时注入（transient）", exp_2c)
exp("2d. 消息持久注入（Command）", exp_2d)
exp("2e. 动态工具选择（按角色）", exp_2e)
exp("2f. 动态响应格式（收窄候选）", exp_2f)
exp("2g-A. 工具结果清理：自写瞬时截断", exp_2g_transient)
exp("2g-B. 工具结果清理：内置 ContextEditing", exp_2g_editing)

# ============================================================
section("3. 工具上下文（读写）")
# ============================================================


@dataclass
class UserCtx:
    user_id: str


def exp_3a():
    """工具读运行时上下文：用 user_id 完成查询。"""

    @tool
    def get_my_user_id(runtime: ToolRuntime[UserCtx]) -> str:
        """查询当前用户的 ID。"""
        return f"当前用户 ID 是 {runtime.context.user_id}"

    agent = create_agent(model, tools=[get_my_user_id], context_schema=UserCtx)
    r = agent.invoke(
        {"messages": [{"role": "user", "content": "请查询我的用户 ID 并告诉我。"}]},
        context=UserCtx(user_id="user_777"),
    )
    print("  回答:", brief(r["messages"][-1].content, 90), flush=True)
    show_chain(r["messages"])


def exp_3b():
    """工具读写状态：login 写（Command）→ check_auth 读。"""

    class AuthState(AgentState):
        authenticated: NotRequired[bool]

    @tool
    def login(password: str, runtime: ToolRuntime) -> Command:
        """登录系统。密码为 correct 时登录成功。"""
        ok = password == "correct"
        # 注意：本版本要求 Command.update 中必须包含对应的 ToolMessage
        # （官方示例的纯 state 更新会报 ValueError，见讲义实测记录）
        return Command(update={
            "messages": [ToolMessage(f"登录{'成功' if ok else '失败'}", tool_call_id=runtime.tool_call_id)],
            "authenticated": ok,
        })

    @tool
    def check_auth(runtime: ToolRuntime) -> str:
        """查询当前登录状态。"""
        return f"当前登录状态：authenticated = {runtime.state.get('authenticated', False)}"

    agent = create_agent(model, tools=[login, check_auth], state_schema=AuthState)
    r = agent.invoke({
        "messages": [{"role": "user", "content": "请先用密码 correct 登录，然后查询当前登录状态。"}]
    })
    print("  回答:", brief(r["messages"][-1].content, 120), flush=True)
    show_chain(r["messages"])
    print(f"  最终状态里的 authenticated = {r.get('authenticated')}（工具通过 Command 写入）", flush=True)


def exp_3c():
    """工具写 store：保存偏好 + 换会话读回（跨会话持久）。"""
    store = InMemoryStore()

    @tool
    def save_preference(key: str, value: str, runtime: ToolRuntime[UserCtx]) -> str:
        """把用户偏好保存到长期存储。"""
        prefs = runtime.store.get(("preferences",), runtime.context.user_id)
        data = dict(prefs.value) if prefs else {}
        data[key] = value
        runtime.store.put(("preferences",), runtime.context.user_id, data)
        return f"已保存偏好：{key} = {value}"

    @tool
    def get_preference(key: str, runtime: ToolRuntime[UserCtx]) -> str:
        """从长期存储读取用户偏好。"""
        item = runtime.store.get(("preferences",), runtime.context.user_id)
        if item and key in item.value:
            return f"{key} = {item.value[key]}"
        return f"未找到偏好 {key}"

    agent = create_agent(
        model, tools=[save_preference, get_preference],
        context_schema=UserCtx, store=store,
    )
    print("  会话 A（thread sess-A）：保存偏好", flush=True)
    r1 = agent.invoke(
        {"messages": [{"role": "user", "content": "请保存我的偏好：语言 = 中文。"}]},
        config={"configurable": {"thread_id": "sess-A"}},
        context=UserCtx(user_id="user_777"),
    )
    print("  回答:", brief(r1["messages"][-1].content, 90), flush=True)

    print("  会话 B（thread sess-B，全新对话）：读取偏好", flush=True)
    r2 = agent.invoke(
        {"messages": [{"role": "user", "content": "请读取我的偏好：语言。"}]},
        config={"configurable": {"thread_id": "sess-B"}},
        context=UserCtx(user_id="user_777"),
    )
    print("  回答:", brief(r2["messages"][-1].content, 90), flush=True)
    item = store.get(("preferences",), "user_777")
    print(f"  store 直查: {item.value if item else None}", flush=True)


exp("3a. 工具读运行时上下文", exp_3a)
exp("3b. 工具读写状态（Command）", exp_3b)
exp("3c. 工具写 store（跨会话）", exp_3c)

# ============================================================
section("4. 生命周期上下文")
# ============================================================


def exp_4a():
    """摘要（SummarizationMiddleware）：持久更新状态（原文被替换）。"""
    agent = create_agent(
        model, tools=[],
        middleware=[
            SummarizationMiddleware(
                model=model,
                trigger=("messages", 4),
                keep=("messages", 2),
            )
        ],
        checkpointer=InMemorySaver(),
    )
    cfg = {"configurable": {"thread_id": "ctx-sum"}}
    turns = [
        "我叫小明，是一名后端工程师，最近在系统学习 LangChain。",
        "请用一句话概括：短期记忆和长期记忆的区别是什么？",
        "我叫什么名字？做什么工作？请简短回答。",
    ]
    for i, msg in enumerate(turns, 1):
        r = agent.invoke({"messages": [{"role": "user", "content": msg}]}, cfg)
        print(f"  第 {i} 轮后消息数: {len(r['messages'])}", flush=True)
    print("  最终状态消息链:", flush=True)
    show_chain(r["messages"], limit=100)
    has_summary = any("summary of the conversation" in str(getattr(m, "content", ""))
                      for m in r["messages"])
    raw_intro = any("我叫小明，是一名后端工程师" == str(getattr(m, "content", "")).strip()
                    for m in r["messages"])
    print(f"  存在摘要消息: {has_summary}（应为 True——摘要持久写入状态）", flush=True)
    print(f"  原始自我介绍消息仍在: {raw_intro}（应为 False——原文已被摘要替换）", flush=True)


def exp_4b():
    """自定义生命周期钩子：计数 + token 审计 → 沉淀到 store。"""

    class AuditState(AgentState):
        model_calls: NotRequired[int]
        total_input_tokens: NotRequired[int]

    class AuditMiddleware(AgentMiddleware):
        state_schema = AuditState

        def after_model(self, state, runtime):
            calls = state.get("model_calls", 0) + 1
            last = state["messages"][-1]
            usage = getattr(last, "usage_metadata", None) or {}
            total = state.get("total_input_tokens", 0) + usage.get("input_tokens", 0)
            return {"model_calls": calls, "total_input_tokens": total}

        def after_agent(self, state, runtime):
            runtime.store.put(("audit",), "sess-9", {
                "model_calls": state.get("model_calls"),
                "total_input_tokens": state.get("total_input_tokens"),
            })
            return None

    @tool
    def get_weather(city: str) -> str:
        """查询一个城市的天气。"""
        return f"{city}：晴天，22°C"

    store = InMemoryStore()
    agent = create_agent(
        model, tools=[get_weather], middleware=[AuditMiddleware()], store=store,
    )
    r = agent.invoke({"messages": [{"role": "user", "content": "查一下北京天气，然后简短汇报。"}]})
    print("  回答:", brief(r["messages"][-1].content, 90), flush=True)
    print(f"  最终状态: model_calls = {r.get('model_calls')}, "
          f"total_input_tokens = {r.get('total_input_tokens')}", flush=True)
    item = store.get(("audit",), "sess-9")
    print(f"  store 中的审计记录: {item.value if item else None}", flush=True)


exp("4a. 摘要：持久更新状态", exp_4a)
exp("4b. 自定义审计钩子（状态计数 → store 沉淀）", exp_4b)

print("\n（全部实验完成）", flush=True)
