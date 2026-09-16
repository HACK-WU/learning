"""课 7 正式实验脚本：Memory 记忆（短期 + 长期，全流程实测）。

设计 5 大板块（对应 4 个知识点）：
1. 记忆机制总览：无状态对照（无 checkpointer / 有 checkpointer / 换线程）
2. 短期记忆：全量增长 → 裁剪 → 摘要 → 自定义 state（工具读写）
3. 长期记忆：store 直操作 → 跨线程召回 → 用户隔离 → 更新
4. 记忆工程实践：profile 合并更新（含覆盖写对照）+ 三种策略成本对比

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0 / langgraph 1.2.11
默认模型：百炼 qwen3.8-flash
说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import os
from dataclasses import dataclass

from dotenv import load_dotenv
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import SummarizationMiddleware, before_model
from langchain.chat_models import init_chat_model
from langchain.messages import RemoveMessage, ToolMessage
from langchain.tools import ToolRuntime, tool
from langchain_core.messages.utils import count_tokens_approximately
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph.message import REMOVE_ALL_MESSAGES
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command

load_dotenv()

model = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
    max_retries=2,
    timeout=60,
)


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}")


def brief(content, limit: int = 110) -> str:
    text = str(content) if content is not None else ""
    text = " ".join(text.split())
    return text[:limit]


def show_chain(msgs, limit: int = 70) -> None:
    """打印消息链（角色 + 摘要，工具调用单列）。"""
    for i, m in enumerate(msgs):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            calls = "; ".join(
                f"{tc['name']}({tc['args']})" for tc in m.tool_calls
            )
            print(f"    [{i}] ai → 调用工具: {calls}")
        else:
            print(f"    [{i}] {t}: {brief(m.content, limit)}")


def chat(agent, text, label, config=None, context=None):
    kwargs = {}
    if config is not None:
        kwargs["config"] = config
    if context is not None:
        kwargs["context"] = context
    r = agent.invoke({"messages": [{"role": "user", "content": text}]}, **kwargs)
    ans = brief(r["messages"][-1].content)
    n = len(r["messages"])
    print(f"  [{label}] {ans}")
    print(f"       （消息数: {n}）")
    return r


# ============================================================
section("1. 记忆机制总览：无状态对照")
# ============================================================

print("\n-- 1a. 无 checkpointer：两次 invoke 相互独立 --")
agent_bare = create_agent(model, tools=[])
r = agent_bare.invoke({"messages": [{"role": "user", "content": "你好，我叫小明。"}]})
print("  [无记忆·第1轮]", brief(r["messages"][-1].content))
r = agent_bare.invoke({"messages": [{"role": "user", "content": "我叫什么名字？"}]})
print("  [无记忆·第2轮]", brief(r["messages"][-1].content))

print("\n-- 1b. 有 checkpointer + 同一 thread_id：历史自动接续 --")
agent_mem = create_agent(model, tools=[], checkpointer=InMemorySaver())
cfg_a = {"configurable": {"thread_id": "thread-A"}}
chat(agent_mem, "我叫小明，最喜欢蓝色。请记住。", "同线程·第1轮", config=cfg_a)
st = agent_mem.get_state(cfg_a)
print("  状态核验（get_state）——已持久化的消息链:")
show_chain(st.values["messages"])
chat(agent_mem, "我叫什么？最喜欢什么颜色？", "同线程·第2轮", config=cfg_a)

print("\n-- 1c. 换一个 thread_id：记忆相互隔离 --")
cfg_b = {"configurable": {"thread_id": "thread-B"}}
chat(agent_mem, "我叫什么？", "新线程·问名字", config=cfg_b)

# ============================================================
section("2. 短期记忆：增长、裁剪、摘要、自定义 state")
# ============================================================

TURNS = [
    "你好，我叫小明。",
    "我喜欢蓝色。",
    "我住在北京。",
    "我养了一只猫，叫咪咪。",
]
CHECK = "我叫什么名字？我喜欢什么颜色？"

print("\n-- 2a. 默认行为：全量积累（越聊越长） --")
agent_full = create_agent(model, tools=[], checkpointer=InMemorySaver())
cfg_f = {"configurable": {"thread_id": "growth"}}
r_full = None
for i, msg in enumerate(TURNS, 1):
    r_full = agent_full.invoke(
        {"messages": [{"role": "user", "content": msg}]}, config=cfg_f
    )
    print(f"  第 {i} 轮后消息数: {len(r_full['messages'])}")
r_full = agent_full.invoke({"messages": [{"role": "user", "content": CHECK}]}, config=cfg_f)
print("  [全量·检查]", brief(r_full["messages"][-1].content))
print(f"       （消息数: {len(r_full['messages'])}）")
full_msgs = r_full["messages"]

print("\n-- 2b. 裁剪：只保留「首条 + 最近 4 条」 --")


@before_model
def trim_messages(state, runtime):
    """保留第一条消息与最近 4 条，控制上下文规模。"""
    messages = state["messages"]
    if len(messages) <= 6:
        return None
    first = messages[0]
    recent = messages[-4:]
    return {"messages": [RemoveMessage(id=REMOVE_ALL_MESSAGES), first, *recent]}


agent_trim = create_agent(
    model, tools=[], middleware=[trim_messages], checkpointer=InMemorySaver()
)
cfg_t = {"configurable": {"thread_id": "trimmed"}}
r_trim = None
for i, msg in enumerate(TURNS, 1):
    r_trim = agent_trim.invoke(
        {"messages": [{"role": "user", "content": msg}]}, config=cfg_t
    )
    print(f"  第 {i} 轮后消息数: {len(r_trim['messages'])}")
r_trim = agent_trim.invoke({"messages": [{"role": "user", "content": CHECK}]}, config=cfg_t)
print("  [裁剪·检查]", brief(r_trim["messages"][-1].content))
print(f"       （消息数: {len(r_trim['messages'])}）")
print("  最终保留的消息链:")
show_chain(r_trim["messages"])
trim_msgs = r_trim["messages"]

print("\n-- 2c. 摘要：超阈值时把早期历史压缩为一条摘要 --")
agent_sum = create_agent(
    model,
    tools=[],
    middleware=[
        SummarizationMiddleware(
            model=model,
            trigger=("messages", 6),
            keep=("messages", 4),
        )
    ],
    checkpointer=InMemorySaver(),
)
cfg_s = {"configurable": {"thread_id": "summarized"}}
r_sum = None
for i, msg in enumerate(TURNS, 1):
    r_sum = agent_sum.invoke(
        {"messages": [{"role": "user", "content": msg}]}, config=cfg_s
    )
    print(f"  第 {i} 轮后消息数: {len(r_sum['messages'])}")
r_sum = agent_sum.invoke({"messages": [{"role": "user", "content": CHECK}]}, config=cfg_s)
print("  [摘要·检查]", brief(r_sum["messages"][-1].content))
print(f"       （消息数: {len(r_sum['messages'])}）")
print("  最终保留的消息链:")
show_chain(r_sum["messages"], limit=110)
sum_msgs = r_sum["messages"]

print("\n-- 2d. 自定义 state：工具读 / 写短期记忆 --")


class CustomState(AgentState):
    user_name: str


@tool
def save_name(name: str, runtime: ToolRuntime) -> Command:
    """记录用户的名字到状态。"""
    return Command(
        update={
            "user_name": name,
            "messages": [
                ToolMessage(f"已记录：{name}", tool_call_id=runtime.tool_call_id)
            ],
        }
    )


@tool
def get_name(runtime: ToolRuntime) -> str:
    """查询之前记录的用户名字。"""
    name = runtime.state.get("user_name")
    return f"之前记录的用户名是：{name}" if name else "没有记录过。"


agent_state = create_agent(
    model,
    tools=[save_name, get_name],
    state_schema=CustomState,
    checkpointer=InMemorySaver(),
)
cfg_st = {"configurable": {"thread_id": "custom-state"}}
r_st = agent_state.invoke(
    {"messages": [{"role": "user", "content": "我的名字是小明，请记录下来。"}]},
    config=cfg_st,
)
print("  [写状态] 消息链:")
show_chain(r_st["messages"])
r_st = agent_state.invoke(
    {"messages": [{"role": "user", "content": "我之前说我的名字是什么？"}]},
    config=cfg_st,
)
print("  [读状态]", brief(r_st["messages"][-1].content))

# ============================================================
section("3. 长期记忆：store 与跨会话")
# ============================================================

print("\n-- 3a. store 基础操作（直接操作，不经模型） --")
store1 = InMemoryStore()
store1.put(("users",), "user_123", {"name": "小明", "language": "中文"})
store1.put(("users",), "user_456", {"name": "小红", "language": "英文"})
item = store1.get(("users",), "user_123")
print("  get(('users',), 'user_123'):", item.value)
items = store1.search(("users",))
print("  search(('users',)) 全部:", [i.value for i in items])
items = store1.search(("users",), filter={"language": "中文"})
print("  search(filter={'language': '中文'}):", [i.value for i in items])
try:
    items = store1.search(("users",), query="名字")
    print("  search(query='名字')（未配嵌入函数）:", [i.value for i in items])
except Exception as e:
    print("  search(query=...) 抛错:", type(e).__name__, str(e)[:100])


print("\n-- 3b. 跨线程召回：session-1 里教，session-2 里查 --")


@dataclass
class UserContext:
    user_id: str


store2 = InMemoryStore()


@tool
def save_user_name(name: str, runtime: ToolRuntime[UserContext]) -> str:
    """保存用户名字到长期记忆（跨会话）。"""
    runtime.store.put(("users",), runtime.context.user_id, {"name": name})
    return f"已保存：{name}"


@tool
def get_user_name(runtime: ToolRuntime[UserContext]) -> str:
    """从长期记忆读取用户名字（跨会话）。"""
    item = runtime.store.get(("users",), runtime.context.user_id)
    return item.value["name"] if item else "没有找到该用户的记录"


agent_lt = create_agent(
    model,
    tools=[save_user_name, get_user_name],
    store=store2,
    context_schema=UserContext,
    checkpointer=InMemorySaver(),
)
cfg_s1 = {"configurable": {"thread_id": "session-1"}}
cfg_s2 = {"configurable": {"thread_id": "session-2"}}
cfg_s3 = {"configurable": {"thread_id": "session-3"}}

r_lt = agent_lt.invoke(
    {"messages": [{"role": "user", "content": "你好，记住：我叫小明。"}]},
    config=cfg_s1,
    context=UserContext(user_id="user_123"),
)
print("  [session-1·教] 消息链:")
show_chain(r_lt["messages"])
print("  直连 store 查看:", store2.get(("users",), "user_123").value)

r_lt = agent_lt.invoke(
    {"messages": [{"role": "user", "content": "我叫什么名字？"}]},
    config=cfg_s2,
    context=UserContext(user_id="user_123"),
)
print("  [session-2·查]", brief(r_lt["messages"][-1].content))
print("       （session-2 的新消息链只有本轮问答——见下方链）")
show_chain(r_lt["messages"])

print("\n-- 3c. 用户隔离：换个 user_id 查不到 --")
r_lt = agent_lt.invoke(
    {"messages": [{"role": "user", "content": "我叫什么名字？"}]},
    config=cfg_s3,
    context=UserContext(user_id="user_456"),
)
print("  [session-3·user_456 查]", brief(r_lt["messages"][-1].content))

print("\n-- 3d. 更新记忆：改名字（put 覆盖同 key） --")
r_lt = agent_lt.invoke(
    {"messages": [{"role": "user", "content": "我要改个名字：以后叫我大明。"}]},
    config=cfg_s1,
    context=UserContext(user_id="user_123"),
)
print("  [session-1·改名] 消息链:")
show_chain(r_lt["messages"])
print("  直连 store 查看:", store2.get(("users",), "user_123").value)

# ============================================================
section("4. 记忆工程实践：更新模式与成本对比")
# ============================================================

print("\n-- 4a. profile 合并更新（读取 → 合并 → 写回） --")
store3 = InMemoryStore()
store3.put(("users",), "u1", {"name": "小明", "city": "北京"})


@tool
def remember_preference(preference: str, runtime: ToolRuntime[UserContext]) -> str:
    """记住用户的偏好（读取现有档案，追加到 preferences 列表后写回）。"""
    ns = ("users",)
    key = runtime.context.user_id
    item = runtime.store.get(ns, key)
    profile = dict(item.value) if item else {}
    prefs = list(profile.get("preferences", []))
    prefs.append(preference)
    profile["preferences"] = prefs
    runtime.store.put(ns, key, profile)
    return f"已记住。当前档案: {profile}"


agent_prof = create_agent(
    model,
    tools=[remember_preference],
    store=store3,
    context_schema=UserContext,
)
print("  更新前:", store3.get(("users",), "u1").value)
r_prof = agent_prof.invoke(
    {"messages": [{"role": "user", "content": "记住：我喜欢喝咖啡。"}]},
    context=UserContext(user_id="u1"),
)
print("  [合并更新] 消息链:")
show_chain(r_prof["messages"])
print("  更新后（合并）:", store3.get(("users",), "u1").value)

store3.put(("users",), "u1", {"preferences": ["喜欢喝咖啡"]})
print("  对照·若直接覆盖写（只写新内容不读旧档案）:", store3.get(("users",), "u1").value)

print("\n-- 4b. 同对话三策略成本对比（消息数 / token 估算） --")
print(f"  {'策略':<6} | {'消息数':<5} | {'token 估算':<8} | 检查问题的回答")
for name, msgs in [("全量", full_msgs), ("裁剪", trim_msgs), ("摘要", sum_msgs)]:
    est = count_tokens_approximately(msgs)
    ans = brief(msgs[-1].content, 60)
    print(f"  {name:<6} | {len(msgs):<7} | {est:<12} | {ans}")

print("\n（全部实验完成）")
