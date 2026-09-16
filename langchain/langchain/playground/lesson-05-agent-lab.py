"""第 5 课 · Agents 实验：loop 流转 / 返回解读 / 结构化输出 / harness 配置。

运行（在 playground 目录内）：

    uv run python lesson-05-agent-lab.py

覆盖：create_agent 参数全景 · agent loop 三站流转 · invoke 返回解读 ·
      结构化输出（含 thinking 模式适配）· system_prompt 两形态 · 动态模型路由 ·
      checkpointer 多轮 · recursion_limit 保护。

说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import inspect
import json
import os
from typing import Union

from dotenv import load_dotenv
from langchain.agents import create_agent
from langchain.agents.middleware import ModelRequest, ModelResponse, wrap_model_call
from langchain.agents.structured_output import ToolStrategy
from langchain.chat_models import init_chat_model
from langchain.messages import SystemMessage
from langchain.tools import tool
from langgraph.checkpoint.memory import InMemorySaver
from pydantic import BaseModel, Field

load_dotenv()

API_KEY = os.environ["BAILIAN_API_KEY"]
BASE_URL = os.environ["BAILIAN_BASE_URL"]

model = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=API_KEY,
    base_url=BASE_URL,
    max_retries=2,
    timeout=60,
)

# 结构化输出专用：关闭 thinking 的同一模型（见 3c 段原因）
model_nothink = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=API_KEY,
    base_url=BASE_URL,
    max_retries=2,
    timeout=60,
    extra_body={"enable_thinking": False},
)

# 动态路由的"高级模型"
model_advanced = init_chat_model(
    "deepseek-v4.1-flash",
    model_provider="openai",
    api_key=API_KEY,
    base_url=BASE_URL,
    max_retries=2,
    timeout=60,
)


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}")


def dump_chain(res, limit: int = 100) -> None:
    """打印一条完整消息链（人话版）。"""
    for i, m in enumerate(res["messages"]):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            for tc in m.tool_calls:
                print(f"  [{i}] AI 请求: {tc['name']}({json.dumps(tc['args'], ensure_ascii=False)})")
        else:
            print(f"  [{i}] {t}: {str(m.content)[:limit]}")


def ledger(res) -> None:
    """给这次运行记账：模型调用与工具执行各多少次。"""
    ai_msgs = [m for m in res["messages"] if getattr(m, "type", "") == "ai"]
    tool_msgs = [m for m in res["messages"] if getattr(m, "type", "") == "tool"]
    n_calls = sum(len(getattr(m, "tool_calls", None) or []) for m in ai_msgs)
    print(
        f"   [账本] 模型被调用 {len(ai_msgs)} 次；工具申请 {n_calls} 条；"
        f"工具回执 {len(tool_msgs)} 条；消息共 {len(res['messages'])} 条"
    )


# ================= 1. 参数全景 =================
section("1. create_agent 签名（本机版本参数全景）")

sig = inspect.signature(create_agent)
for name, p in sig.parameters.items():
    default = "" if p.default is inspect.Parameter.empty else f" = {p.default!r}"
    print(f"  {name}{default}")
print("  返回:", str(sig.return_annotation)[:80], "…")


# ================= 1b. 引擎的图结构（拆开看） =================
@tool
def get_order(order_id: str) -> str:
    """查询订单明细，返回商品、单价、数量、运费（不含总价）。"""
    orders = {
        "A1024": "订单 A1024：机械键盘 x2，单价 349 元；运费 12 元",
        "B2048": "订单 B2048：显示器支架 x1，单价 199 元；运费 0 元",
    }
    return orders.get(order_id, f"未找到订单 {order_id}")


section("1b. 引擎的图结构（拆开看）")
agent_g = create_agent(model, tools=[get_order])
g = agent_g.get_graph()
print("节点清单:")
for n in g.nodes:
    print("  -", n)
print("\n边清单:")
for e in g.edges:
    cond = "（条件边）" if getattr(e, "conditional", False) else ""
    print(f"  {e.source} -> {e.target} {cond}")


# ================= 2. agent loop 三站 =================
# 工具 get_order 已在 1b 段定义，下面补充本课另两个工具。
@tool("calculator", description="执行四则运算。任何数学计算都必须用它。")
def calc(expression: str) -> str:
    """Evaluate mathematical expressions."""
    allowed = set("0123456789+-*/(). ")
    if set(expression) - allowed:
        return "仅支持数字与 +-*/() 运算"
    return str(eval(expression, {"__builtins__": {}}, {}))


@tool
def set_reminder(content: str, when: str) -> str:
    """设置一条提醒。content 为提醒内容，when 为时间描述。"""
    return f"已设置提醒 [{when}]：{content}"


section("2a. 站一：无工具——一步结束（模型直接说话）")
agent0 = create_agent(model, tools=[])
res0 = agent0.invoke({"messages": [{"role": "user", "content": "请用一句话说明什么是 agent loop。"}]})
dump_chain(res0)
ledger(res0)

section("2b. 站二：两圈循环——查订单 → 算账 → 终答")
agent1 = create_agent(model, tools=[get_order, calc])
res1 = agent1.invoke(
    {"messages": [{"role": "user", "content": "帮我算下订单 A1024 一共要付多少钱（含运费）"}]}
)
dump_chain(res1)
ledger(res1)

section("2c. 站三：多圈任务——查订单 → 算账 → 设提醒 → 终答")
agent2 = create_agent(model, tools=[get_order, calc, set_reminder])
res2 = agent2.invoke(
    {
        "messages": [
            {
                "role": "user",
                "content": "帮我算下订单 A1024 总共多少钱，算完再设一个明天上午 10 点的提醒：给客户回电话",
            }
        ]
    }
)
dump_chain(res2)
ledger(res2)

section("2d. 返回结构：invoke 结果里有什么")
print("返回类型:", type(res2).__name__)
print("keys:", list(res2.keys()))
print("最后一条消息类型:", type(res2["messages"][-1]).__name__)
print("最后一条消息 tool_calls:", getattr(res2["messages"][-1], "tool_calls", None))


# ================= 3. 结构化输出 =================
class ContactInfo(BaseModel):
    """联系人信息。"""

    name: str = Field(description="姓名")
    email: str = Field(description="邮箱")
    phone: str = Field(description="电话")


Q_CONTACT = "从这段信息中提取联系人：John Doe, john@example.com, (555) 123-4567"

section("3a. 结构化输出：默认模型（thinking 模式）→ 被服务端拒绝（复现）")
try:
    agent_s0 = create_agent(model, tools=[], response_format=ContactInfo)
    res_s0 = agent_s0.invoke({"messages": [{"role": "user", "content": Q_CONTACT}]})
    print("未报错？structured_response:", repr(res_s0.get("structured_response")))
except Exception as e:
    print("失败 →", type(e).__name__, "|", str(e)[:200])

section("3b. 结构化输出：关闭 thinking 后 → 成功")
agent_s = create_agent(model_nothink, tools=[], response_format=ContactInfo)
res_s = agent_s.invoke({"messages": [{"role": "user", "content": Q_CONTACT}]})
print("返回 keys:", list(res_s.keys()))
sr = res_s.get("structured_response")
print("structured_response:", repr(sr))
print("类型:", type(sr).__name__)
dump_chain(res_s)


class ProductRating(BaseModel):
    rating: int = Field(description="评分，1 到 5", ge=1, le=5)
    comment: str = Field(description="评价内容")


section("3c. 结构化输出：校验失败 → 自动重试（10/10 超出 1-5）")
agent_r = create_agent(
    model_nothink,
    tools=[],
    response_format=ToolStrategy(ProductRating),
    system_prompt="你是评价解析助手，严格按用户输入解析，不要擅自改动数值。",
)
res_r = agent_r.invoke({"messages": [{"role": "user", "content": "解析这条评价：Amazing product, 10/10!"}]})
print("structured_response:", repr(res_r.get("structured_response")))
dump_chain(res_r, limit=150)


class EventDetails(BaseModel):
    """事件信息。"""

    event_name: str = Field(description="事件名称")
    date: str = Field(description="事件日期")


section("3d. 结构化输出的重试机制：模型一次调了两个（Union 场景）")
agent_u = create_agent(
    model_nothink,
    tools=[],
    response_format=ToolStrategy(Union[ContactInfo, EventDetails]),
)
res_u = agent_u.invoke(
    {
        "messages": [
            {
                "role": "user",
                "content": "Extract info: John Doe (john@email.com) is organizing Tech Conference on March 15th",
            }
        ]
    }
)
print("structured_response:", repr(res_u.get("structured_response")))
dump_chain(res_u, limit=170)


# ================= 4. harness 配置 =================
section("4a. system_prompt 对照：无提示词 vs 角色提示词")
Q_SELF = "请介绍一下你自己。"
agent_np = create_agent(model, tools=[])
res_np = agent_np.invoke({"messages": [{"role": "user", "content": Q_SELF}]})
print("[无提示词]", str(res_np["messages"][-1].content)[:110])

agent_p = create_agent(model, tools=[], system_prompt="你是海盗船长，用海盗口吻回答，不超过两句话。")
res_p = agent_p.invoke({"messages": [{"role": "user", "content": Q_SELF}]})
print("[海盗提示词]", str(res_p["messages"][-1].content)[:110])

section("4b. system_prompt 接收 SystemMessage 对象")
agent_p2 = create_agent(
    model, tools=[], system_prompt=SystemMessage("你是严谨的学术助手，每次回答必须以【学术模式】开头。")
)
res_p2 = agent_p2.invoke({"messages": [{"role": "user", "content": Q_SELF}]})
print("[SystemMessage 形态]", str(res_p2["messages"][-1].content)[:130])

section("4c. 动态模型选择：@wrap_model_call 按对话长度路由")


@wrap_model_call
def dynamic_model_selection(request: ModelRequest, handler) -> ModelResponse:
    """对话超过 2 条消息时，切到更强的模型。"""
    n = len(request.state["messages"])
    if n > 2:
        chosen, m = "deepseek-v4.1-flash（高级）", model_advanced
    else:
        chosen, m = "qwen3.8-flash（基础）", model
    print(f"    [路由] 当前 {n} 条消息 → 选用 {chosen}")
    return handler(request.override(model=m))


agent_dyn = create_agent(
    model=model, tools=[], middleware=[dynamic_model_selection], checkpointer=InMemorySaver()
)
cfg_dyn = {"configurable": {"thread_id": "thread-dyn"}}
print("第一轮（1 条消息）:")
r_d1 = agent_dyn.invoke({"messages": [{"role": "user", "content": "一句话解释什么是函数。"}]}, config=cfg_dyn)
print("  →", str(r_d1["messages"][-1].content)[:100])
print("第二轮（携带历史，消息数变多）:")
r_d2 = agent_dyn.invoke({"messages": [{"role": "user", "content": "再举个例子。"}]}, config=cfg_dyn)
print("  →", str(r_d2["messages"][-1].content)[:100])

section("4d. checkpointer + thread_id：多轮对话记住身份")
agent_c = create_agent(model, tools=[], checkpointer=InMemorySaver())
cfg = {"configurable": {"thread_id": "thread-001"}}
r_c1 = agent_c.invoke({"messages": [{"role": "user", "content": "我叫小明，最喜欢蓝色。请记住。"}]}, config=cfg)
print("第一轮回复:", str(r_c1["messages"][-1].content)[:90])
r_c2 = agent_c.invoke({"messages": [{"role": "user", "content": "我叫什么？最喜欢什么颜色？"}]}, config=cfg)
print("第二轮回复:", str(r_c2["messages"][-1].content)[:130])
print("第二轮返回的消息总数（含本轮与历史）:", len(r_c2["messages"]))

agent_nc = create_agent(model, tools=[])
r_c3 = agent_nc.invoke({"messages": [{"role": "user", "content": "我叫什么？最喜欢什么颜色？"}]})
print("对照（无 checkpointer 的新 agent）:", str(r_c3["messages"][-1].content)[:130])


# ================= 5. 保护机制 =================
section("5. recursion_limit 保护：步数预算耗尽会报错")
try:
    res5 = agent1.invoke(
        {"messages": [{"role": "user", "content": "帮我算下订单 A1024 一共要付多少钱（含运费）"}]},
        config={"recursion_limit": 4},
    )
    print("未触发保护，消息数:", len(res5["messages"]))
except Exception as e:
    print("触发 →", type(e).__name__, "|", str(e)[:260])

print("\n（全部实验完成）")
