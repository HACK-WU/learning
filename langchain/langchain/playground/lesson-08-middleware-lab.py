"""课 8 正式实验脚本：Middleware 中间件（机制 / 内置 / 自定义 / 组合顺序，全流程实测）。

设计 4 大板块（对应 4 个知识点）：
1. 机制：单中间件钩子全景（六个钩子的触发时刻与顺序）
2. 内置：ModelCallLimit / ToolCallLimit / ToolRetry / ToolError / ModelFallback / PII / ToolSelector / TodoList
3. 自定义：装饰器式（计数 + 自定义 state）、类式（内容守护 + jump 提前结束）
4. 组合：三中间件执行顺序（before 正序 / after 逆序 / wrap 嵌套）、顺序影响行为（工具选择器与观察者换位）

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0 / langgraph 1.2.11
默认模型：百炼 qwen3.8-flash
说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import os
from typing import Any

from dotenv import load_dotenv
from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import (
    AgentMiddleware,
    LLMToolSelectorMiddleware,
    ModelCallLimitMiddleware,
    ModelFallbackMiddleware,
    PIIMiddleware,
    TodoListMiddleware,
    ToolCallLimitMiddleware,
    ToolErrorMiddleware,
    ToolRetryMiddleware,
    after_model,
    before_model,
    wrap_model_call,
)
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, ToolMessage
from langchain.tools import tool
from langgraph.checkpoint.memory import InMemorySaver
from typing_extensions import NotRequired

load_dotenv()

API_KEY = os.environ["BAILIAN_API_KEY"]
BASE_URL = os.environ["BAILIAN_BASE_URL"]


def make_model(name="qwen3.8-flash", **kw):
    return init_chat_model(
        name, model_provider="openai",
        api_key=API_KEY, base_url=BASE_URL, max_retries=2, timeout=60, **kw,
    )


model = make_model()


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(content, limit: int = 110) -> str:
    text = str(content) if content is not None else ""
    text = " ".join(text.split())
    return text[:limit]


def show_chain(msgs, limit: int = 80) -> None:
    for i, m in enumerate(msgs):
        t = getattr(m, "type", type(m).__name__)
        if t == "ai" and getattr(m, "tool_calls", None):
            calls = "; ".join(f"{tc['name']}({tc['args']})" for tc in m.tool_calls)
            print(f"    [{i}] ai → 调用工具: {calls}", flush=True)
        else:
            print(f"    [{i}] {t}: {brief(m.content, limit)}", flush=True)


# ---------------- 公共工具 ----------------

@tool
def calculator(expression: str) -> str:
    """计算一个算术表达式，例如 '12*8'。"""
    return f"{expression} = {eval(expression)}"  # noqa: S307  # 教学演示


@tool
def get_weather(city: str) -> str:
    """查询一个城市的天气。"""
    return f"{city}：晴天，22°C"


@tool
def get_time(city: str) -> str:
    """查询一个城市的当前时间。"""
    return f"{city} 当前时间 14:30"


# ============================================================
section("1. 机制：单中间件钩子全景")
# ============================================================


class HookTourMiddleware(AgentMiddleware):
    """按触发顺序打印全部六个钩子。"""

    def before_agent(self, state, runtime):
        print("  【钩子】before_agent（每次调用一次）", flush=True)
        return None

    def before_model(self, state, runtime):
        print(f"  【钩子】before_model（第 {len(state['messages'])} 条消息已就位）", flush=True)
        return None

    def after_model(self, state, runtime):
        print("  【钩子】after_model（模型刚返回）", flush=True)
        return None

    def after_agent(self, state, runtime):
        print("  【钩子】after_agent（agent 结束）", flush=True)
        return None

    def wrap_model_call(self, request, handler):
        print("  【钩子】wrap_model_call 进入 →（调用内层/模型）", flush=True)
        response = handler(request)
        print("  【钩子】wrap_model_call 返回", flush=True)
        return response

    def wrap_tool_call(self, request, handler):
        name = request.tool_call["name"]
        print(f"  【钩子】wrap_tool_call 进入 → 即将执行工具 {name}", flush=True)
        result = handler(request)
        print(f"  【钩子】wrap_tool_call 返回 ← 工具 {name} 完成", flush=True)
        return result


agent_hook = create_agent(model, tools=[calculator], middleware=[HookTourMiddleware()])

print("\n-- 1a. 一次带工具的调用，钩子触发顺序 --", flush=True)
r = agent_hook.invoke({"messages": [{"role": "user", "content": "请用计算器算 6*7。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链:", flush=True)
show_chain(r["messages"])

# ============================================================
section("2. 内置中间件")
# ============================================================

print("\n-- 2a. ModelCallLimitMiddleware：run_limit=2，超额优雅收尾 --", flush=True)
agent_mcl = create_agent(
    model,
    tools=[get_weather, get_time],
    middleware=[ModelCallLimitMiddleware(run_limit=2, exit_behavior="end")],
)
r = agent_mcl.invoke({
    "messages": [{"role": "user", "content": "先查北京天气，再查北京当前时间，最后给一句出行建议。"}]
})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链（注意最后一条）:", flush=True)
show_chain(r["messages"])

print("\n-- 2b. ToolCallLimitMiddleware：calculator 限 1 次，超额拦下 --", flush=True)
agent_tcl = create_agent(
    model,
    tools=[calculator],
    middleware=[ToolCallLimitMiddleware(tool_name="calculator", run_limit=1)],
)
r = agent_tcl.invoke({
    "messages": [{"role": "user", "content": "请连续用计算器算两次：先算 12*8，再算 15*7。"}]
})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链（注意被拦下的第二次调用）:", flush=True)
show_chain(r["messages"])

print("\n-- 2c. ToolRetryMiddleware：前两次失败、第三次成功 --", flush=True)
_attempts = {"n": 0}


@tool
def flaky_service(query: str) -> str:
    """查询一个不稳定的外部服务。"""
    _attempts["n"] += 1
    n = _attempts["n"]
    print(f"    （工具实际被执行：第 {n} 次）", flush=True)
    if n <= 2:
        raise RuntimeError(f"服务暂时不可用（第 {n} 次尝试失败）")
    return f"查询成功：{query} 的结果是 42"


agent_retry = create_agent(
    model,
    tools=[flaky_service],
    middleware=[
        ToolRetryMiddleware(max_retries=3, initial_delay=0.05, backoff_factor=0.0, jitter=False)
    ],
)
r = agent_retry.invoke({"messages": [{"role": "user", "content": "请查询订单 A100 的结果。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链:", flush=True)
show_chain(r["messages"])

print("\n-- 2d. ToolErrorMiddleware：工具抛异常，转成错误消息交给模型 --", flush=True)


@tool
def strict_divide(a: float, b: float) -> str:
    """做除法，除数为 0 时抛异常。"""
    if b == 0:
        raise ValueError("除数不能为 0")
    return f"{a} / {b} = {a / b}"


print("  对照组（无中间件）：", flush=True)
agent_plain = create_agent(model, tools=[strict_divide])
try:
    agent_plain.invoke({"messages": [{"role": "user", "content": "请算 10 除以 0。"}]})
    print("    （未抛异常——与课 4 结论不符，需复核）", flush=True)
except Exception as e:
    print(f"    agent 中断：{type(e).__name__}: {str(e)[:100]}", flush=True)

print("  实验组（ToolErrorMiddleware）：", flush=True)


def on_error(exc: Exception, request) -> str | None:
    if isinstance(exc, ValueError):
        return f"`{request.tool_call['name']}` 执行失败（{type(exc).__name__}），请调整输入后重试。"
    return None


agent_err = create_agent(
    model,
    tools=[strict_divide],
    middleware=[ToolErrorMiddleware(on_error)],
)
r = agent_err.invoke({"messages": [{"role": "user", "content": "请算 10 除以 0。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链:", flush=True)
show_chain(r["messages"])

print("\n-- 2e. ModelFallbackMiddleware：主模型不可用，自动降级 --", flush=True)
bad_model = make_model("qwen3.8-flash-nonexistent")
agent_fb = create_agent(
    bad_model,
    tools=[],
    middleware=[ModelFallbackMiddleware(model)],
)
try:
    r = agent_fb.invoke({"messages": [{"role": "user", "content": "用一个词回答：你还好吗？"}]})
    print("  最终回答（来自降级模型）:", brief(r["messages"][-1].content), flush=True)
except Exception as e:
    print(f"  降级未生效：{type(e).__name__}: {str(e)[:150]}", flush=True)

print("\n-- 2f. PIIMiddleware：邮箱脱敏 + 卡号掩码 --", flush=True)
agent_pii = create_agent(
    model,
    tools=[],
    middleware=[
        PIIMiddleware("email", strategy="redact", apply_to_input=True),
        PIIMiddleware("credit_card", strategy="mask", apply_to_input=True),
    ],
)
r = agent_pii.invoke({
    "messages": [{"role": "user", "content": "请原样复述这两个信息：邮箱 zhangsan@example.com，卡号 4111 1111 1111 1111。"}]
})
print("  最终回答:", brief(r["messages"][-1].content, 160), flush=True)

print("\n-- 2g. LLMToolSelectorMiddleware：max_tools=2 过滤工具 --", flush=True)
# 用装饰器快速补几个无关工具
@tool
def translate_text(text: str) -> str:
    """把文本翻译成英文。"""
    return f"[EN] {text}"


@tool
def tell_joke() -> str:
    """讲一个笑话。"""
    return "为什么程序员总是分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。"


@tool
def unit_convert(value: float, unit: str) -> str:
    """换算单位。"""
    return f"{value} {unit} 已换算"


@tool
def book_flight(city: str) -> str:
    """预订机票。"""
    return f"已预订飞往 {city} 的机票"


pool = [get_weather, translate_text, tell_joke, unit_convert, book_flight, get_time]

agent_sel = create_agent(
    model,
    tools=pool,
    middleware=[LLMToolSelectorMiddleware(model=model, max_tools=2)],
)
r = agent_sel.invoke({"messages": [{"role": "user", "content": "北京今天天气怎么样？"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链（实际调用的工具）:", flush=True)
show_chain(r["messages"])

print("\n-- 2h. TodoListMiddleware：复杂任务先列计划 --", flush=True)
agent_todo = create_agent(
    model,
    tools=[get_weather, get_time],
    middleware=[TodoListMiddleware()],
)
r = agent_todo.invoke({
    "messages": [{"role": "user", "content": "这是一个多步任务：第一步查北京天气，第二步查北京当前时间，第三步把两者汇总成一句出行建议。请按步骤执行。"}]
})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息链（注意 write_todos 调用）:", flush=True)
show_chain(r["messages"], limit=100)

# ============================================================
section("3. 自定义中间件")
# ============================================================

print("\n-- 3a. 装饰器式：计数 + 自定义 state（model_call_count） --", flush=True)


class CounterState(AgentState):
    model_call_count: NotRequired[int]


@before_model(state_schema=CounterState)
def log_before(state: CounterState, runtime):
    print(f"  [自定义] before_model：即将进行第 {state.get('model_call_count', 0) + 1} 次模型调用", flush=True)
    return None


@after_model(state_schema=CounterState)
def count_after(state: CounterState, runtime):
    c = state.get("model_call_count", 0) + 1
    print(f"  [自定义] after_model：模型调用计数 → {c}", flush=True)
    return {"model_call_count": c}


agent_cnt = create_agent(
    model,
    tools=[calculator],
    middleware=[log_before, count_after],
)
r = agent_cnt.invoke({"messages": [{"role": "user", "content": "请用计算器算 8*9。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  最终状态里的计数 model_call_count =", r.get("model_call_count"), flush=True)

print("\n-- 3b. 装饰器式：内容守护 + jump 提前结束 --", flush=True)
# 注：守卫在 before_model 拦截，触发时跳过模型直接收尾


@before_model(can_jump_to=["end"])
def content_guard(state, runtime):
    last = state["messages"][-1]
    text = str(last.content)
    if "禁止话题" in text:
        print("  [守护] 检测到敏感输入，跳过模型直接收尾", flush=True)
        return {
            "messages": [AIMessage("抱歉，这个话题我不能处理。")],
            "jump_to": "end",
        }
    return None


agent_guard = create_agent(model, tools=[], middleware=[content_guard])

print("  场景一（正常输入）：", flush=True)
r = agent_guard.invoke({"messages": [{"role": "user", "content": "用一句话说你好。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)

print("  场景二（触发守护）：", flush=True)
r = agent_guard.invoke({"messages": [{"role": "user", "content": "我们来聊禁止话题吧。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)
print("  消息数（应为 2：输入 + 兜底回复，无模型输出）:", len(r["messages"]), flush=True)
show_chain(r["messages"])

# ============================================================
section("4. 组合与执行顺序")
# ============================================================


class OrderMiddleware(AgentMiddleware):
    def __init__(self, tag: str):
        super().__init__()
        self.tag = tag

    @property
    def name(self) -> str:
        return f"order-{self.tag}"

    def before_agent(self, state, runtime):
        print(f"  [{self.tag}] before_agent", flush=True)
        return None

    def before_model(self, state, runtime):
        print(f"  [{self.tag}] before_model", flush=True)
        return None

    def after_model(self, state, runtime):
        print(f"  [{self.tag}] after_model", flush=True)
        return None

    def after_agent(self, state, runtime):
        print(f"  [{self.tag}] after_agent", flush=True)
        return None

    def wrap_model_call(self, request, handler):
        print(f"  [{self.tag}] wrap_model_call 进入", flush=True)
        response = handler(request)
        print(f"  [{self.tag}] wrap_model_call 返回", flush=True)
        return response

    def wrap_tool_call(self, request, handler):
        print(f"  [{self.tag}] wrap_tool_call 进入", flush=True)
        result = handler(request)
        print(f"  [{self.tag}] wrap_tool_call 返回", flush=True)
        return result


print("\n-- 4a. 三个中间件（M1, M2, M3）的钩子触发顺序 --", flush=True)
agent_order = create_agent(
    model,
    tools=[calculator],
    middleware=[OrderMiddleware("M1"), OrderMiddleware("M2"), OrderMiddleware("M3")],
)
r = agent_order.invoke({"messages": [{"role": "user", "content": "请用计算器算 1234*5678。"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)

print("\n-- 4b. 顺序影响行为：观察者与工具选择器换位 --", flush=True)


class ToolObserver(AgentMiddleware):
    """打印当前模型能看到的工具清单。"""

    def wrap_model_call(self, request, handler):
        names = []
        for t in (request.tools or []):
            names.append(getattr(t, "name", str(t)))
        print(f"  [观察者] 模型可见工具（{len(names)} 个）: {names}", flush=True)
        return handler(request)


print("  顺序 A：selector 在前（外层），观察者在后（内层）", flush=True)
agent_o1 = create_agent(
    model,
    tools=pool,
    middleware=[LLMToolSelectorMiddleware(model=model, max_tools=2), ToolObserver()],
)
r = agent_o1.invoke({"messages": [{"role": "user", "content": "北京今天天气怎么样？"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)

print("  顺序 B：观察者在前（外层），selector 在后（内层）", flush=True)
agent_o2 = create_agent(
    model,
    tools=pool,
    middleware=[ToolObserver(), LLMToolSelectorMiddleware(model=model, max_tools=2)],
)
r = agent_o2.invoke({"messages": [{"role": "user", "content": "北京今天天气怎么样？"}]})
print("  最终回答:", brief(r["messages"][-1].content), flush=True)

print("\n（全部实验完成）", flush=True)
