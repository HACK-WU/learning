"""第 4 课 · 工具实验：定义 / schema / 绑定 / 执行 / 校验 / 错误 / 运行时上下文 / 动态选择。

运行（在 playground 目录内）：

    uv run python lesson-04-tools-lab.py

说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import json
import os
from dataclasses import dataclass
from typing import Literal

from collections.abc import Callable

from dotenv import load_dotenv
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import wrap_tool_call
from langchain.chat_models import init_chat_model
from langchain.messages import HumanMessage, ToolMessage
from langchain.tools import ToolRuntime, tool
from langchain.tools.tool_node import ToolCallRequest
from langchain_core.utils.function_calling import convert_to_openai_tool
from langgraph.store.memory import InMemoryStore
from langgraph.types import Command
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


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}")


def dump_chain(res, limit: int = 90) -> None:
    """打印一条完整消息链（人话版）。"""
    for m in res["messages"]:
        t = getattr(m, "type", "?")
        if t == "ai" and getattr(m, "tool_calls", None):
            for tc in m.tool_calls:
                print(f"   [AI 请求] {tc['name']}({json.dumps(tc['args'], ensure_ascii=False)})")
        elif t == "tool":
            print(f"   [Tool 回执] {str(m.content)[:limit]}")
        else:
            print(f"   [{t}] {str(m.content)[:limit]}")


def last_ai(res) -> str:
    for m in reversed(res["messages"]):
        if getattr(m, "type", "") == "ai" and getattr(m, "content", ""):
            return str(m.content)
    return "（无 AI 文本）"


# ================= 1. 定义一个工具 =================
section("1a. @tool 基本用法：docstring 与类型标注")


@tool
def search_database(query: str, limit: int = 10) -> str:
    """Search the customer database for records matching the query.

    Args:
        query: Search terms to look for
        limit: Maximum number of results to return
    """
    return f"Found {limit} results for '{query}'"


print("name:", search_database.name)
print("description:", repr(search_database.description))
print("args_schema:")
print(json.dumps(search_database.args_schema.model_json_schema(), ensure_ascii=False, indent=2))

section("1b. parse_docstring 开关：Args 段的描述会不会进 schema")


@tool(parse_docstring=True)
def search_v2(query: str, limit: int = 10) -> str:
    """Search the customer database for records matching the query.

    Args:
        query: Search terms to look for
        limit: Maximum number of results to return
    """
    return f"Found {limit} results for '{query}'"


print(json.dumps(search_v2.args_schema.model_json_schema(), ensure_ascii=False, indent=2))

section("1c. 属性定制：自定义名字与描述")


@tool("web_search")
def search(query: str) -> str:
    """Search the web for information."""
    return f"Results for: {query}"


ALLOWED_CHARS = set("0123456789+-*/(). ")


@tool("calculator", description="Performs arithmetic calculations. Use this for any math problems.")
def calc(expression: str) -> str:
    """Evaluate mathematical expressions."""
    if set(expression) - ALLOWED_CHARS:
        return "仅支持数字与 +-*/() 运算"
    return str(eval(expression, {"__builtins__": {}}, {}))


print("name:", search.name)
print("name:", calc.name, "| description:", calc.description)

section("1d. 没有 docstring / 没有类型标注会怎样")
try:

    @tool
    def no_doc(x: str) -> str:
        return x

except Exception as e:
    print("无 docstring:", type(e).__name__, "|", str(e)[:120])

try:

    @tool
    def no_hints(a, b):
        """Add two numbers."""
        return a + b

    print("无类型标注的 schema:", json.dumps(no_hints.args_schema.model_json_schema(), ensure_ascii=False))
except Exception as e:
    print("无类型标注:", type(e).__name__, "|", str(e)[:160])

section("1e. Pydantic schema：复杂参数与校验规则")


class WeatherInput(BaseModel):
    """Input for weather queries."""

    location: str = Field(description="City name or coordinates")
    units: Literal["celsius", "fahrenheit"] = Field(
        default="celsius", description="Temperature unit preference"
    )
    include_forecast: bool = Field(default=False, description="Include 5-day forecast")


@tool(args_schema=WeatherInput)
def get_weather(location: str, units: str = "celsius", include_forecast: bool = False) -> str:
    """Get current weather and optional forecast."""
    temp = 22 if units == "celsius" else 72
    result = f"Current weather in {location}: {temp} degrees {units[0].upper()}"
    if include_forecast:
        result += "\nNext 5 days: Sunny"
    return result


print(json.dumps(get_weather.args_schema.model_json_schema(), ensure_ascii=False, indent=2))

section("1f. runtime 参数不进 schema（对模型隐藏）")


@tool
def get_message_count(runtime: ToolRuntime) -> str:
    """Get the number of messages in the conversation."""
    return f"共 {len(runtime.state['messages'])} 条消息"


@tool
def get_user_preference(pref_name: str, runtime: ToolRuntime) -> str:
    """Get a user preference value."""
    return f"偏好 {pref_name} 的值为 xxx"


print("args_schema 字段（工具内部全貌，含注入参数）:")
print("  ", list(get_message_count.args_schema.model_fields.keys()))
print("tool_call_schema 字段（模型看到的）:")
print("  ", list(get_message_count.tool_call_schema.model_fields.keys()))
print("混合参数工具 get_user_preference，模型实际收到:")
print(json.dumps(convert_to_openai_tool(get_user_preference), ensure_ascii=False, indent=1))
print("（对比：普通工具的 args_schema.model_json_schema() 即模型所见）")

section("1g. 保留参数名（config / runtime）")


try:

    @tool
    def needs_config(config: str) -> str:
        """测试保留名。"""
        return config

    try:
        out = needs_config.invoke({"config": "hello"})
        print("定义成功 & 调用返回:", out)
    except Exception as e:
        print("定义成功，调用报错:", type(e).__name__, "|", str(e)[:150])
except Exception as e:
    print("定义报错:", type(e).__name__, "|", str(e)[:150])

# ================= 2. 参数校验 =================
section("2. 参数校验行为（直接 invoke）")

print("正常调用:", get_weather.invoke({"location": "北京"}))

for payload, tag in [
    ({"location": "北京", "units": "kelvin"}, "units 非法值"),
    ({}, "缺 location"),
    ({"location": "北京", "extra": 1}, "多余参数"),
    ({"location": 123}, "类型不对"),
]:
    try:
        out = get_weather.invoke(payload)
        print(f"[{tag}] 未报错，返回: {str(out)[:80]}")
    except Exception as e:
        print(f"[{tag}] {type(e).__name__}: {str(e)[:170]}")

# ================= 3. 绑定与选择 =================
section("3. bind_tools 与工具选择（真实模型）")
mw = model.bind_tools([search_database, calc])
r = mw.invoke("帮我算 23*17 是多少")
print("问题: 帮我算 23*17 是多少")
print("tool_calls:", r.tool_calls)

# ================= 4. 并行调用 + 手动闭环 =================
section("4a. 并行工具请求（一个提问、两个调用）")
mw2 = model.bind_tools([get_weather])
q = HumanMessage("北京和上海的天气分别怎么样？")
r1 = mw2.invoke([q])
print("tool_calls 数量:", len(r1.tool_calls))
for tc in r1.tool_calls:
    print(f"  - {tc['name']} args={json.dumps(tc['args'], ensure_ascii=False)} id={tc['id'][:20]}...")

section("4b. 手动执行循环（tool.invoke(tool_call) 直接吐 ToolMessage）")
msgs = [q, r1]
for tc in r1.tool_calls:
    tm = get_weather.invoke(tc)
    print(
        f"执行 {tc['args']['location']} -> 返回类型: {type(tm).__name__}, "
        f"tool_call_id 匹配: {tm.tool_call_id == tc['id']}"
    )
    msgs.append(tm)

final = mw2.invoke(msgs)
print("最终答复:", final.content)

# ================= 5. 错误处理 =================
section("5a. 工具抛异常（直接调用）")


@tool
def query_stock_price(stock_code: str) -> str:
    """查询 A 股股票的最新价格。股票代码必须是 6 位数字（如 600519）。"""
    prices = {"600519": "贵州茅台：1688.00 元", "000001": "平安银行：12.34 元"}
    if stock_code not in prices:
        raise ValueError(f"股票代码 {stock_code} 未收录")
    return prices[stock_code]


try:
    query_stock_price.invoke({"stock_code": "300999"})
except Exception as e:
    print("直接调用:", type(e).__name__, "|", str(e)[:130])

section("5b-1. 默认行为：业务异常直接冒泡（打断 agent）")


_LOADED: dict = {"dataset": None}


@tool
def load_dataset(name: str) -> str:
    """从磁盘加载指定名称的数据集文件（仅当数据集尚未加载时使用）。"""
    _LOADED["dataset"] = name
    return f"数据集 {name} 已加载，共 1000 行。"


@tool
def analyze() -> str:
    """报告当前数据集的整体统计。"""
    if _LOADED["dataset"] is None:
        raise ValueError("分析失败：尚未加载数据集。先调用 load_dataset（可试用 name='demo'）再重试。")
    return f"数据集 {_LOADED['dataset']}：共 1000 行，平均分 87.5，无缺失值。"


agent_err = create_agent(model, tools=[load_dataset, analyze])
try:
    res = agent_err.invoke({"messages": [{"role": "user", "content": "帮我看看数据集的整体情况"}]})
    print("未崩溃？完整消息链:")
    dump_chain(res, limit=110)
except Exception as e:
    print("5b-1 默认行为：agent 直接崩溃 →", type(e).__name__, "|", str(e)[:300])


section("5b-2. 标准做法：wrap_tool_call 中间件转换异常 → 模型自我修正")


@wrap_tool_call
def handle_tool_errors(request: ToolCallRequest, handler: Callable) -> ToolMessage:
    """把工具异常转成模型能读懂的 ToolMessage（官方工具页写法）。"""
    try:
        return handler(request)
    except Exception as e:
        return ToolMessage(
            content=f"Tool error: Please check your input and try again. ({e})",
            tool_call_id=request.tool_call["id"],
        )


_LOADED["dataset"] = None  # 重置状态：从"未加载"开始，观察完整修正循环
agent_err2 = create_agent(model, tools=[load_dataset, analyze], middleware=[handle_tool_errors])
res = agent_err2.invoke({"messages": [{"role": "user", "content": "帮我看看数据集的整体情况"}]})
print("完整消息链（出错 → 修正 → 成功）:")
dump_chain(res, limit=130)
print("最终答复:", str(last_ai(res))[:150])

# ================= 6. ToolRuntime =================
section("6. ToolRuntime：上下文注入 / 状态读取 / 长期记忆")


@dataclass
class UserContext:
    user_id: str
    user_name: str


@tool
def who_am_i(runtime: ToolRuntime[UserContext]) -> str:
    """获取当前用户的信息。"""
    n = len(runtime.state["messages"])
    return f"用户: {runtime.context.user_name}（id={runtime.context.user_id}）｜对话 {n} 条消息｜tool_call_id={runtime.tool_call_id}"


@tool
def save_color(color: str, runtime: ToolRuntime[UserContext]) -> str:
    """保存用户喜欢的颜色到长期记忆。"""
    runtime.store.put(("prefs",), runtime.context.user_id, {"favorite_color": color})
    return f"已保存：{color}"


@tool
def read_color(runtime: ToolRuntime[UserContext]) -> str:
    """读取用户喜欢的颜色（从长期记忆）。"""
    item = runtime.store.get(("prefs",), runtime.context.user_id)
    if item is None:
        return "长期记忆中没有记录"
    return f"你喜欢的颜色是：{item.value['favorite_color']}"


store = InMemoryStore()
agent_rt = create_agent(
    model,
    tools=[who_am_i, save_color, read_color],
    context_schema=UserContext,
    store=store,
)

ctx = UserContext(user_id="user123", user_name="小明")

res1 = agent_rt.invoke({"messages": [{"role": "user", "content": "我是谁？"}]}, context=ctx)
print("6a. 问『我是谁』→", str(last_ai(res1))[:160])

res2 = agent_rt.invoke({"messages": [{"role": "user", "content": "请记住：我喜欢的颜色是蓝色"}]}, context=ctx)
print("6b. 保存颜色 →", str(last_ai(res2))[:120])

res3 = agent_rt.invoke({"messages": [{"role": "user", "content": "我喜欢的颜色是什么？"}]}, context=ctx)
print("6c. 新会话读取 →", str(last_ai(res3))[:120])

print("6d. 从外部直查存储桶:")
for item in store.search(("prefs",)):
    print("   ", item.namespace, item.key, item.value)

# ================= 7. 动态工具选择 =================
section("7. 动态工具选择：按角色给不同的工具集")


_DATA_STATE = {"deleted": False}


@tool
def read_data(table: str) -> str:
    """读取数据表内容。"""
    if _DATA_STATE["deleted"]:
        return f"（{table} 表数据：0 行，已清空）"
    return f"（{table} 表数据：128 行）"


@tool
def write_data(table: str, value: str) -> str:
    """写入数据表。"""
    return f"（已写入 {table}）"


@tool
def delete_data(table: str) -> dict:
    """删除数据表的全部数据（高危操作）。"""
    _DATA_STATE["deleted"] = True
    return {"deleted": True, "table": table, "rows": 128}


viewer_agent = create_agent(model, tools=[read_data])
admin_agent = create_agent(model, tools=[read_data, write_data, delete_data])

q7 = "请删除 orders 数据表里的全部数据"

res_v = viewer_agent.invoke({"messages": [{"role": "user", "content": q7}]})
print("7a. viewer（只给 read_data）→", str(last_ai(res_v))[:160])

res_a = admin_agent.invoke({"messages": [{"role": "user", "content": q7}]})
print("7b. admin 第一轮（模型先提出风险警示）:")
dump_chain(res_a, limit=110)

print("7c. 用户确认后（携带历史继续）：")
res_a2 = admin_agent.invoke(
    {
        "messages": res_a["messages"]
        + [{"role": "user", "content": "我已确认，这是测试环境，允许执行删除，请直接调用工具执行。"}]
    }
)
dump_chain({"messages": res_a2["messages"][len(res_a["messages"]):]}, limit=110)

# ================= 8. Command：写入 agent 状态 =================
section("8. 工具更新 agent 状态（Command 返回值）")


class CustomState(AgentState):
    user_name: str


@tool
def set_user_name(new_name: str, runtime: ToolRuntime[None, CustomState]) -> Command:
    """Set the user's name in the conversation state."""
    return Command(
        update={
            "user_name": new_name,
            "messages": [
                ToolMessage(
                    content=f"用户名已设置为 {new_name}。",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )


agent_state = create_agent(model, tools=[set_user_name], state_schema=CustomState)

res8 = agent_state.invoke({"messages": [{"role": "user", "content": "请把我的用户名设置为小明"}]})
print("最终状态里的 user_name:", res8.get("user_name"))
dump_chain(res8, limit=100)
