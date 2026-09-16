"""课 12 正式实验脚本：Multi-Agent 多智能体全流程实测。

设计 3 大板块（对应 3 个知识点）：
1. 为什么需要多智能体：单 agent 全能架构的上下文成本 vs 拆分后的隔离
2. 核心模式：subagents（含并行调度/上下文隔离）/ handoffs（中间件型 + 子图型）/ router（分类-并行-综合）
3. 进阶模式与选择：skills（渐进披露 + 行为对照）/ custom workflow（确定性+agentic 混合）
   / 四模式同名任务对照（one-shot + repeat 调用次数）

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0 / langgraph 1.2.11
默认模型：百炼 qwen3.8-flash
说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import json
import os
import time
from typing import Annotated, Literal, TypedDict

from dotenv import load_dotenv

load_dotenv()

import operator

from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import ModelRequest, ModelResponse, wrap_model_call
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, ToolMessage
from langchain.tools import ToolRuntime, tool
from langchain_core.callbacks import BaseCallbackHandler
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command, Send
from typing_extensions import NotRequired

model = init_chat_model(
    "qwen3.8-flash", model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
    max_retries=2, timeout=60,
)


class CountHandler(BaseCallbackHandler):
    """统计模型调用次数的回调。"""

    def __init__(self):
        self.calls = 0

    def on_chat_model_start(self, serialized, messages, **kwargs):
        self.calls += 1


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(content, limit: int = 140) -> str:
    text = str(content) if content is not None else ""
    return " ".join(text.split())[:limit]


def exp(label: str, fn) -> None:
    print(f"\n-- {label} --", flush=True)
    t0 = time.time()
    try:
        fn()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {brief(e, 200)}", flush=True)
    print(f"  [本项耗时 {time.time() - t0:.1f}s]", flush=True)


def show_chain(msgs, limit: int = 90, max_items: int = 14) -> None:
    shown = msgs if len(msgs) <= max_items else msgs[:4] + ['...'] + msgs[-6:]
    for m in shown:
        if m == '...':
            print(f"    ...（中间省略 {len(msgs) - 10} 条）", flush=True)
            continue
        t = getattr(m, 'type', type(m).__name__)
        if t == 'ai' and getattr(m, 'tool_calls', None):
            for tc in m.tool_calls:
                print(f"    [{t}] ai -> tool: {tc['name']}({brief(tc['args'], 66)})", flush=True)
        elif t == 'tool':
            print(f"    [{t}] tool 返回: {brief(m.content, limit)}", flush=True)
        elif t == 'ai':
            print(f"    [{t}] ai: {brief(m.content, limit)}", flush=True)
        else:
            print(f"    [{t}]: {brief(m.content, limit)}", flush=True)


# ============================================================
# 站一：为什么需要多智能体——单 agent 全能 vs 领域拆分
# ============================================================

@tool
def get_weather(city: str) -> str:
    """查询指定城市的当前天气。"""
    return f"{city}：晴，22°C，湿度 40%，东南风 2 级"


@tool
def get_stock(symbol: str) -> str:
    """查询股票的当前价格。"""
    data = {"AAPL": "189.5 美元", "TSLA": "242.1 美元", "0700.HK": "378 港元"}
    return f"{symbol} 当前价格：{data.get(symbol, '未收录')}"


@tool
def convert_currency(amount: float, from_currency: str, to_currency: str) -> str:
    """货币换算。"""
    return f"{amount} {from_currency} ≈ {amount * 7.1:.1f} {to_currency}（示例汇率 7.1）"


@tool
def explain_sql(sql: str) -> str:
    """解释 SQL 查询的执行计划。"""
    return f"执行计划：全表扫描 -> 索引过滤 -> 排序。共 3 步。（针对: {sql[:40]}...）"


@tool
def send_email(to: str, subject: str) -> str:
    """发送邮件。"""
    return f"邮件已发送给 {to}，主题：{subject}"


@tool
def create_event(title: str, date: str) -> str:
    """创建日历事件。"""
    return f"已创建日程：{title} @ {date}"


@tool
def translate_text(text: str, target_lang: str) -> str:
    """翻译文本。"""
    return f"[{target_lang}] {text}"


@tool
def search_docs(query: str) -> str:
    """搜索内部文档。"""
    return f"找到 3 篇与「{query}」相关的文档：A 指南、B 规范、C 手册"


ALL_TOOLS = [get_weather, get_stock, convert_currency, explain_sql,
             send_email, create_event, translate_text, search_docs]

DOMAIN_KNOWLEDGE = {
    "weather": ("天气领域知识：本系统覆盖全国 300+ 城市的实时天气；"
                "数据每 10 分钟刷新；空气质量指数按国标计算。"),
    "finance": ("金融领域知识：支持 A 股/港股/美股行情；汇率为示例数据；"
                "所有价格延迟 15 分钟；本系统不提供投资建议。"),
    "database": ("数据库领域知识：支持 MySQL/PostgreSQL 执行计划解释；"
                 "建议关注索引命中率与扫描行数；慢查询阈值 1 秒。"),
    "office": ("办公领域知识：邮件发送要求填写完整收件人；"
               "日程创建需含日期；文档搜索覆盖内部 wiki。"),
}

OMNI_PROMPT = (
    "你是全能助手，覆盖四个领域：\n"
    + "\n".join(DOMAIN_KNOWLEDGE.values())
    + "\n根据用户问题选择合适的工具完成任务。"
)

omni_agent = create_agent(model, tools=ALL_TOOLS, system_prompt=OMNI_PROMPT)


def tool_schema_chars(tools) -> int:
    total = 0
    for t in tools:
        schema = t.args_schema.model_json_schema() if hasattr(t.args_schema, 'model_json_schema') else {}
        total += len(json.dumps(schema, ensure_ascii=False))
        total += len(t.name) + len(t.description)
    return total


def exp_1a():
    """1a：两种架构的静态上下文成本（prompt + 工具 schema 字符数）。"""
    omni_cost = len(OMNI_PROMPT) + tool_schema_chars(ALL_TOOLS)
    print(f"  [单 agent 全能架构] system_prompt {len(OMNI_PROMPT)} 字符 "
          f"+ 工具 schema {tool_schema_chars(ALL_TOOLS)} 字符 "
          f"= 共 {omni_cost} 字符（每次模型调用都携带）", flush=True)
    print(f"    挂载工具数: {len(ALL_TOOLS)}（四个领域混在一起）", flush=True)
    print(flush=True)
    # 拆分架构：每个子代理只带自己领域的工具与知识
    splits = {
        "weather": ([get_weather], DOMAIN_KNOWLEDGE["weather"]),
        "finance": ([get_stock, convert_currency], DOMAIN_KNOWLEDGE["finance"]),
        "database": ([explain_sql], DOMAIN_KNOWLEDGE["database"]),
        "office": ([send_email, create_event, translate_text, search_docs], DOMAIN_KNOWLEDGE["office"]),
    }
    print(f"  [拆分架构] 每个子代理只带自己领域的工具与知识：", flush=True)
    sub_costs = []
    for name, (tools, knowledge) in splits.items():
        cost = len(knowledge) + tool_schema_chars(tools)
        sub_costs.append(cost)
        print(f"    {name:9s}: {len(tools)} 个工具 + 领域知识 = {cost} 字符", flush=True)
    print(flush=True)
    # 主代理：只带 4 个子代理工具（不含领域知识）
    subagent_tool_chars = len('weather_expert') + len('finance_expert') + len('database_expert') + len('office_expert')
    subagent_desc_chars = sum(len(d) for d in [
        '查询任意城市的天气。输入城市名称。',
        '查询股票价格与货币换算。输入查询内容。',
        '解释 SQL 执行计划。输入 SQL 语句。',
        '处理邮件、日程、翻译、文档搜索。输入任务内容。',
    ]) + 120
    main_cost = len('你是总协调员。按任务领域调度子代理。') + subagent_tool_chars + subagent_desc_chars
    print(f"  [拆分架构 · 主代理] 只带 4 个子代理工具（无领域知识）= {main_cost} 字符", flush=True)
    print(f"  [对照] 单 agent 每次调用携带 ~{omni_cost} 字符；"
          f"拆分后主代理 ~{main_cost} 字符，子代理按需 ~{min(sub_costs)}-{max(sub_costs)} 字符", flush=True)


def exp_1b():
    """1b：单 agent 对跨领域任务的工具选择行为。"""
    counter = CountHandler()
    q = "帮我做两件事：1) 查一下上海现在的天气；2) 给我看看 AAPL 的股价。"
    print(f"  问题: {q}", flush=True)
    r = omni_agent.invoke(
        {'messages': [{'role': 'user', 'content': q}]},
        config={'callbacks': [counter]},
    )
    print(f"  模型调用: {counter.calls} 次", flush=True)
    print("  消息路径：", flush=True)
    show_chain(r['messages'], limit=100)


# ============================================================
# 站二：三大核心模式
# ============================================================

# ---- 子代理工厂 ----

def make_specialist(name: str, tools, knowledge: str, desc: str):
    agent = create_agent(model, tools=tools, system_prompt=knowledge)

    @tool(name, description=desc)
    def call_specialist(query: str) -> str:
        result = agent.invoke({'messages': [{'role': 'user', 'content': query}]})
        return result['messages'][-1].content

    return call_specialist


weather_expert = make_specialist(
    'weather_expert', [get_weather], DOMAIN_KNOWLEDGE['weather'],
    '查询天气。输入城市名称，返回该城市天气。',
)
finance_expert = make_specialist(
    'finance_expert', [get_stock, convert_currency], DOMAIN_KNOWLEDGE['finance'],
    '查询股票价格或做货币换算。输入查询内容。',
)
database_expert = make_specialist(
    'database_expert', [explain_sql], DOMAIN_KNOWLEDGE['database'],
    '解释 SQL 执行计划。输入 SQL 语句。',
)

MAIN_PROMPT = (
    "你是总协调员。你自己不直接处理领域任务，而是调度相应的领域专家（子代理工具）：\n"
    "- weather_expert：天气相关\n"
    "- finance_expert：股票、汇率相关\n"
    "- database_expert：SQL、数据库相关\n"
    "接到任务后，把每个子任务交给对应的专家，最后汇总它们的答复回复用户。"
)

main_agent = create_agent(model, tools=[weather_expert, finance_expert, database_expert],
                          system_prompt=MAIN_PROMPT)


def exp_2a():
    counter = CountHandler()
    q = '杭州今天天气怎么样？'
    print(f"  问题: {q}", flush=True)
    r = main_agent.invoke(
        {'messages': [{'role': 'user', 'content': q}]},
        config={'callbacks': [counter]},
    )
    print(f"  模型调用总数: {counter.calls} 次（主代理 2 + 子代理内部 2）", flush=True)
    print("  主会话消息路径（注意：子代理内部消息不可见）：", flush=True)
    show_chain(r['messages'], limit=100)


def exp_2b():
    counter = CountHandler()
    q = ('帮我并行处理三件事：1) 查一下成都的天气；2) 看看 TSLA 股价；'
         '3) 解释这条 SQL：SELECT * FROM orders WHERE user_id = 42')
    print(f"  问题: {q}", flush=True)
    r = main_agent.invoke(
        {'messages': [{'role': 'user', 'content': q}]},
        config={'callbacks': [counter]},
    )
    print(f"  模型调用总数: {counter.calls} 次", flush=True)
    print("  消息路径（观测主代理是否一次发起多个子代理调用）：", flush=True)
    show_chain(r['messages'], limit=90)


def exp_2c():
    """上下文隔离：主代理记住的信息，子代理不会自动知道。"""
    print("  [对照组] 直接把'帮我查一下天气'交给子代理（无任何历史）：", flush=True)
    bare_weather = create_agent(model, tools=[get_weather], system_prompt=DOMAIN_KNOWLEDGE['weather'])
    r0 = bare_weather.invoke({'messages': [{'role': 'user', 'content': '帮我查一下天气。'}]})
    print(f"    子代理回复: {brief(r0['messages'][-1].content, 160)}", flush=True)
    print(flush=True)
    print("  [实验组] 主代理两轮对话（先用 checkpointer 记住城市）：", flush=True)
    agent = create_agent(
        model, tools=[weather_expert],
        system_prompt=MAIN_PROMPT + '\n用户之前提到的城市信息请记在心里，调度天气专家时把城市传给它。',
        checkpointer=InMemorySaver(),
    )
    cfg = {'configurable': {'thread_id': 'pre-2c'}}
    r1 = agent.invoke({'messages': [{'role': 'user', 'content': '我在上海工作。'}]}, cfg)
    print(f"    第 1 轮（告知信息）: 主代理回复 {brief(r1['messages'][-1].content, 90)}", flush=True)
    r2 = agent.invoke({'messages': [{'role': 'user', 'content': '帮我查一下天气。'}]}, cfg)
    print(f"    第 2 轮（未提城市）消息路径：", flush=True)
    show_chain(r2['messages'], limit=100)
    print(f"    → 观测点：主代理是否从历史中取出'上海'并传给 weather_expert", flush=True)


# ---- 2d: handoffs（single agent with middleware）三阶段流程 ----

class SupportState(AgentState):
    current_step: str = 'triage'
    device: str | None = None
    warranty: str | None = None
    symptom: str | None = None


@tool
def record_warranty(device: str, warranty: str, runtime: ToolRuntime[None, SupportState]) -> Command:
    """记录设备型号与保修状态，进入诊断阶段。warranty 取值: in_warranty / out_of_warranty"""
    return Command(update={
        'messages': [ToolMessage(content=f'已记录：{device} / {warranty}', tool_call_id=runtime.tool_call_id)],
        'device': device,
        'warranty': warranty,
        'current_step': 'diagnose',
    })


@tool
def diagnose_issue(symptom: str, runtime: ToolRuntime[None, SupportState]) -> Command:
    """记录故障现象，进入解决方案阶段。"""
    return Command(update={
        'messages': [ToolMessage(content=f'诊断完成：{symptom}', tool_call_id=runtime.tool_call_id)],
        'symptom': symptom,
        'current_step': 'resolution',
    })


@tool
def provide_solution() -> str:
    """给出最终解决方案。"""
    return '解决方案：符合免费换屏条件，预约后 3 个工作日完成。'


STEP_CONFIGS = {
    'triage': {
        'prompt': '你是客服分诊员（triage 阶段）。礼貌地询问设备型号与保修状态，并用 record_warranty 工具记录。',
        'tools': [record_warranty],
    },
    'diagnose': {
        'prompt': '你是故障诊断员（diagnose 阶段）。设备与保修已知，请询问故障现象并用 diagnose_issue 工具记录。',
        'tools': [diagnose_issue],
    },
    'resolution': {
        'prompt': '你是维修专家（resolution 阶段）。请先用 provide_solution 工具获取方案，再用友好的语气向用户说明。',
        'tools': [provide_solution],
    },
}

MIDDLEWARE_LOG = []


@wrap_model_call
def apply_step_config(request: ModelRequest, handler) -> ModelResponse:
    step = request.state.get('current_step', 'triage')
    cfg = STEP_CONFIGS[step]
    tool_names = [t.name for t in cfg['tools']]
    MIDDLEWARE_LOG.append((step, tool_names))
    print(f"      [中间件] step={step} | 工具集={tool_names}", flush=True)
    request = request.override(system_prompt=cfg['prompt'], tools=cfg['tools'])
    return handler(request)


support_agent = create_agent(
    model,
    tools=[record_warranty, diagnose_issue, provide_solution],
    state_schema=SupportState,
    middleware=[apply_step_config],
    checkpointer=InMemorySaver(),
)


def exp_2d():
    cfg = {'configurable': {'thread_id': 'pre-2d'}}
    turns = [
        '我的手机屏幕碎了想修。',
        '华为 P60，还在保修期内。',
        '就是昨天摔了一下，屏幕左上角裂了。',
    ]
    for i, q in enumerate(turns, 1):
        print(f"  [第 {i} 轮] 用户: {q}", flush=True)
        r = support_agent.invoke({'messages': [{'role': 'user', 'content': q}]}, cfg)
        print(f"    step={r.get('current_step')} | 回复: {brief(r['messages'][-1].content, 120)}", flush=True)
        print(flush=True)
    print(f"  中间件调用轨迹（step 演进）: {[(s, t) for s, t in MIDDLEWARE_LOG]}", flush=True)


# ---- 2e: handoffs（multiple agent subgraphs）----

class MultiAgentState(AgentState):
    active_agent: NotRequired[str]


@tool
def transfer_to_support(runtime: ToolRuntime) -> Command:
    """把对话转交给技术支持代理。"""
    last_ai = next(msg for msg in reversed(runtime.state['messages']) if isinstance(msg, AIMessage))
    return Command(
        goto='support_agent',
        update={
            'active_agent': 'support_agent',
            'messages': [last_ai, ToolMessage(content='已转接到技术支持代理', tool_call_id=runtime.tool_call_id)],
        },
        graph=Command.PARENT,
    )


@tool
def transfer_to_sales(runtime: ToolRuntime) -> Command:
    """把对话转交给销售代理。"""
    last_ai = next(msg for msg in reversed(runtime.state['messages']) if isinstance(msg, AIMessage))
    return Command(
        goto='sales_agent',
        update={
            'active_agent': 'sales_agent',
            'messages': [last_ai, ToolMessage(content='已转接到销售代理', tool_call_id=runtime.tool_call_id)],
        },
        graph=Command.PARENT,
    )


gateway_sales = create_agent(
    model, tools=[transfer_to_support],
    system_prompt='你是销售代理，负责报价与购买咨询。若客户问技术问题，调用 transfer_to_support 转交。',
)
gateway_support = create_agent(
    model, tools=[transfer_to_sales],
    system_prompt='你是技术支持代理，负责技术问题排查。若客户问价格，调用 transfer_to_sales 转交。',
)


def call_sales(state: MultiAgentState) -> dict:
    return gateway_sales.invoke(state)


def call_support(state: MultiAgentState) -> dict:
    return gateway_support.invoke(state)


def route_after(state: MultiAgentState) -> Literal['sales_agent', 'support_agent', '__end__']:
    msgs = state.get('messages', [])
    if msgs:
        last = msgs[-1]
        if isinstance(last, AIMessage) and not last.tool_calls:
            return '__end__'
    return state.get('active_agent') or 'sales_agent'


def route_initial(state: MultiAgentState) -> Literal['sales_agent', 'support_agent']:
    return state.get('active_agent') or 'sales_agent'


builder = StateGraph(MultiAgentState)
builder.add_node('sales_agent', call_sales)
builder.add_node('support_agent', call_support)
builder.add_conditional_edges(START, route_initial, ['sales_agent', 'support_agent'])
builder.add_conditional_edges('sales_agent', route_after, ['sales_agent', 'support_agent', END])
builder.add_conditional_edges('support_agent', route_after, ['sales_agent', 'support_agent', END])
gateway_graph = builder.compile()


def exp_2e():
    q = '你们这个设备多少钱？另外它连不上网怎么修？'
    print(f"  问题: {q}", flush=True)
    r = gateway_graph.invoke({'messages': [{'role': 'user', 'content': q}]})
    print("  消息路径：", flush=True)
    show_chain(r['messages'], limit=95)
    print(f"  最终 active_agent: {r.get('active_agent')}", flush=True)


# ---- 2f: router（分类 -> 并行分派 -> 综合）----

class RouterState(TypedDict):
    query: str
    subtasks: list[dict]
    results: Annotated[list[str], operator.add]
    final: str


ROUTER_MATERIAL = {
    'tech': '自研大模型平台已支持智能体框架；上线三个月调用量增长 300%。',
    'finance': '差旅报销需在费用发生后 30 天内提交；住宿一线城市上限 600 元/晚。',
    'hr': '年假按司龄阶梯：1-3 年 5 天，3-5 年 10 天，5 年以上 15 天。',
}


def router_classify(state: RouterState) -> dict:
    """分类步骤：用模型判断问题涉及哪些领域（JSON 输出）。"""
    prompt = (
        '判断下面这个问题涉及哪些领域，可多选。领域列表：tech（研发技术）、'
        'finance（财务报销）、hr（人事制度）。\n'
        '只输出 JSON 数组，如 ["tech","finance"]，不要其他文字。\n'
        f'问题：{state["query"]}'
    )
    r = model.invoke(prompt)
    import re
    m = re.search(r'\[[^\]]*\]', r.content)
    domains = json.loads(m.group(0)) if m else ['tech']
    domains = [d for d in domains if d in ROUTER_MATERIAL] or ['tech']
    print(f"  [分类] 命中领域: {domains}", flush=True)
    return {'subtasks': [{'agent': d, 'query': state['query']} for d in domains]}


def make_domain_node(domain: str):
    material = ROUTER_MATERIAL[domain]

    @tool('search_' + domain, description=f'在{domain}知识库中搜索')
    def search(q: str) -> str:
        return f'[{domain}知识库] 与"{q}"相关：{material}'

    agent = create_agent(model, tools=[search], system_prompt=f'你是{domain}领域专家。先检索再基于结果回答。')

    def node(state: dict) -> dict:
        r = agent.invoke({'messages': [{'role': 'user', 'content': state['query']}]})
        return {'results': [f'[{domain}] {r["messages"][-1].content}']}
    return node


def router_fan_out(state: RouterState):
    return [Send(t['agent'], {'query': t['query']}) for t in state['subtasks']]


def router_synthesize(state: RouterState) -> dict:
    joined = '\n'.join(state['results'])
    r = model.invoke(f'把以下多来源信息综合成一段连贯回答（保留关键数字）：\n{joined}')
    return {'final': r.content}


def build_router():
    g = StateGraph(RouterState)
    g.add_node('classify', router_classify)
    for domain in ROUTER_MATERIAL:
        g.add_node(domain, make_domain_node(domain))
    g.add_node('synthesize', router_synthesize)
    g.add_edge(START, 'classify')
    g.add_conditional_edges('classify', router_fan_out, list(ROUTER_MATERIAL.keys()))
    for domain in ROUTER_MATERIAL:
        g.add_edge(domain, 'synthesize')
    g.add_edge('synthesize', END)
    return g.compile()


router_graph = build_router()


def exp_2f():
    counter = CountHandler()
    q = '我们研发同事去上海出差，住宿能报多少？顺便说下我们平台的进展。'
    print(f"  问题: {q}", flush=True)
    r = router_graph.invoke(
        {'query': q, 'subtasks': [], 'results': []},
        config={'callbacks': [counter]},
    )
    print(f"  模型调用总数: {counter.calls} 次（分类 1 + 各领域代理 + 综合 1）", flush=True)
    print(f"  并行结果 {len(r['results'])} 条：", flush=True)
    for res in r['results']:
        print(f"    {brief(res, 110)}", flush=True)
    print(f"  综合回答: {brief(r['final'], 220)}", flush=True)


# ============================================================
# 站三：进阶模式与选择
# ============================================================

# ---- 3a: skills（渐进式披露 + 行为对照）----

SKILLS = {
    'sql_expert': (
        '你是 SQL 专家。写查询时必须遵守：\n'
        '1) 禁止 SELECT *，必须显式列出字段；\n'
        '2) 时间过滤用 WHERE，不要全表扫描；\n'
        '3) 输出结构：先给 SQL，再给一句性能提示。'
    ),
    'legal_reviewer': (
        '你是合同审查专家。审查时逐项检查：违约责任 / 知识产权归属 / 争议解决方式。输出风险清单。'
    ),
}


@tool
def load_skill(skill_name: str) -> str:
    """加载专业技能包。

    可用技能：
    - sql_expert: SQL 查询编写专家
    - legal_reviewer: 合同审查专家
    """
    if skill_name in SKILLS:
        return f'[技能已加载: {skill_name}]\n{SKILLS[skill_name]}'
    return f'未知技能: {skill_name}。可用: {list(SKILLS)}'


def exp_3a():
    counter_s = CountHandler()
    skill_agent = create_agent(
        model, tools=[load_skill],
        system_prompt=('你是通用助手。有两个技能：sql_expert（SQL 编写）与 legal_reviewer（合同审查）。'
                       '任务涉及这些领域时，必须先调用 load_skill 加载对应技能，再按技能要求完成。'),
    )
    q = '帮我写一条 SQL：查询用户表里最近 7 天注册的用户。'
    print(f"  [A 有技能] {q}", flush=True)
    r = skill_agent.invoke(
        {'messages': [{'role': 'user', 'content': q}]},
        config={'callbacks': [counter_s]},
    )
    print(f"    模型调用: {counter_s.calls} 次", flush=True)
    print("    消息路径：", flush=True)
    show_chain(r['messages'], limit=160)
    print(flush=True)
    counter_n = CountHandler()
    bare_agent = create_agent(model, tools=[], system_prompt='你是通用助手。简洁回答。')
    print(f"  [B 无技能对照] {q}", flush=True)
    r2 = bare_agent.invoke(
        {'messages': [{'role': 'user', 'content': q}]},
        config={'callbacks': [counter_n]},
    )
    print(f"    模型调用: {counter_n.calls} 次", flush=True)
    print(f"    回答: {brief(r2['messages'][-1].content, 200)}", flush=True)


# ---- 3b: custom workflow（rewrite -> retrieve -> agent 的 RAG 流水线）----

def exp_3b():
    from pathlib import Path

    from langchain_core.documents import Document
    from langchain_core.vectorstores import InMemoryVectorStore
    from langchain_openai import OpenAIEmbeddings

    emb = OpenAIEmbeddings(
        model=os.environ['SILICONFLOW_EMBEDDING_MODEL'],
        api_key=os.environ['SILICONFLOW_API_KEY'],
        base_url=os.environ['SILICONFLOW_BASE_URL'],
        check_embedding_ctx_length=False,
    )
    kb_dir = Path(__file__).parent / 'kb'
    docs = [Document(page_content=p.read_text(encoding='utf-8'), metadata={'source': p.name})
            for p in sorted(kb_dir.glob('*.md'))]
    store = InMemoryVectorStore(emb)
    store.add_documents(docs)
    retriever = store.as_retriever(search_kwargs={'k': 2})
    print(f"  [准备] 知识库 {len(docs)} 份文档已入库（复用课 11 语料）", flush=True)

    import re

    class WFState(TypedDict):
        question: str
        rewritten: str
        docs: list[str]
        answer: str

    def node_rewrite(state: WFState) -> dict:
        """模型节点：把口语化问题改写为检索友好的关键词。"""
        r = model.invoke(
            '把下面的问题改写成适合检索的关键词（一行，不加解释）：\n' + state['question']
        )
        rw = r.content.strip()
        print(f"    [rewrite 节点] '{state['question']}' -> '{rw[:60]}'", flush=True)
        return {'rewritten': rw}

    def node_retrieve(state: WFState) -> dict:
        """确定性节点：向量检索（无 LLM 参与）。"""
        hits = retriever.invoke(state['rewritten'])
        texts = [f'[{d.metadata["source"]}] {d.page_content[:120]}' for d in hits]
        print(f"    [retrieve 节点] 命中 {len(hits)} 块: {[d.metadata['source'] for d in hits]}", flush=True)
        return {'docs': texts}

    answer_agent = create_agent(
        model, tools=[get_weather],
        system_prompt='你是企业助手。基于给定资料回答问题并注明来源；资料不足时如实说明。',
    )

    def node_agent(state: WFState) -> dict:
        """agentic 节点：基于检索资料生成回答（可调用工具）。"""
        context = '\n'.join(state['docs'])
        r = answer_agent.invoke({'messages': [{'role': 'user',
                                               'content': f'资料：\n{context}\n\n问题：{state["question"]}'}]})
        return {'answer': r['messages'][-1].content}

    wf = (
        StateGraph(WFState)
        .add_node('rewrite', node_rewrite)
        .add_node('retrieve', node_retrieve)
        .add_node('agent', node_agent)
        .add_edge(START, 'rewrite')
        .add_edge('rewrite', 'retrieve')
        .add_edge('retrieve', 'agent')
        .add_edge('agent', END)
        .compile()
    )
    q = '年假怎么请'
    print(f"  问题: {q}", flush=True)
    r = wf.invoke({'question': q})
    print(f"  回答: {brief(r['answer'], 260)}", flush=True)
    print(f"  节点轨迹: rewrite(模型) -> retrieve(确定性) -> agent(agentic)", flush=True)


# ---- 3c: 四模式对照（同一任务：查南京天气）----

def exp_3c():
    print("  任务统一为：'南京今天天气怎么样？'（one-shot 与 repeat 各测一轮）", flush=True)
    print(flush=True)

    # --- A. subagents ---
    print("  [A: subagents]", flush=True)
    cA1 = CountHandler()
    a_main = create_agent(model, tools=[weather_expert],
                          system_prompt='你是总协调员，调度 weather_expert 处理天气任务。')
    cfgA = {'callbacks': [cA1]}
    a_main.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]}, cfgA)
    print(f"    turn1 模型调用: {cA1.calls} 次（主代理决策 + 子代理内部 + 主代理汇总）", flush=True)
    cA2 = CountHandler()
    a_main.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                  {'callbacks': [cA2]})
    print(f"    turn2 模型调用: {cA2.calls} 次（无状态，重走全流程）", flush=True)

    # --- B. skills ---
    print("  [B: skills]", flush=True)

    @tool
    def load_weather_skill() -> str:
        """加载天气流程技能。任务涉及天气查询时必须先加载此技能。"""
        return ('[weather 技能已加载]\n天气查询流程：1) 确认城市；2) 调用 get_weather 工具；'
                '3) 用一句话播报结果（含温度）。')

    skill_agent = create_agent(
        model, tools=[load_weather_skill, get_weather],
        system_prompt='你是助手。执行天气任务前必须先调用 load_weather_skill 加载流程技能，'
                      '再按技能指引完成。如果技能已在对话中加载过，则直接执行。',
    )
    cB1 = CountHandler()
    skill_agent.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                       {'callbacks': [cB1]})
    print(f"    turn1 模型调用: {cB1.calls} 次（加载技能 + 查询 + 回复）", flush=True)
    cB2 = CountHandler()
    skill_agent.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                       {'callbacks': [cB2]})
    print(f"    turn2 模型调用: {cB2.calls} 次（技能已在历史，直接执行）", flush=True)

    # --- C. router ---
    print("  [C: router]", flush=True)

    class MiniRouterState(TypedDict):
        query: str
        final: str

    weather_node_agent = create_agent(
        model, tools=[get_weather], system_prompt='你是天气领域专家。用工具查询后简洁回答。')

    def mini_route(state: MiniRouterState) -> dict:
        r = model.invoke(
            '判断问题是否与天气相关。只输出 WEATHER 或 OTHER。\n问题：' + state['query'])
        print(f"    [分类] {r.content.strip()[:20]}", flush=True)
        return {}

    def mini_weather(state: MiniRouterState) -> dict:
        r = weather_node_agent.invoke({'messages': [{'role': 'user', 'content': state['query']}]})
        return {'final': r['messages'][-1].content}

    g = StateGraph(MiniRouterState)
    g.add_node('classify', mini_route)
    g.add_node('weather', mini_weather)
    g.add_edge(START, 'classify')
    g.add_edge('classify', 'weather')
    g.add_edge('weather', END)
    mini_router = g.compile()
    cC1 = CountHandler()
    mini_router.invoke({'query': '南京今天天气怎么样？'}, {'callbacks': [cC1]})
    print(f"    turn1 模型调用: {cC1.calls} 次（分类 + 领域代理 + 回复）", flush=True)
    cC2 = CountHandler()
    mini_router.invoke({'query': '南京今天天气怎么样？'}, {'callbacks': [cC2]})
    print(f"    turn2 模型调用: {cC2.calls} 次（无状态，重新分类走全流程）", flush=True)

    # --- D. handoffs ---
    print("  [D: handoffs]", flush=True)

    class WState(AgentState):
        current_step: str = 'ask_city'   # ask_city -> ready
        city: str | None = None

    @tool
    def confirm_city(city: str, runtime: ToolRuntime[None, WState]) -> Command:
        """确认城市并进入查询就绪状态。"""
        return Command(update={
            'messages': [ToolMessage(content=f'城市已确认：{city}', tool_call_id=runtime.tool_call_id)],
            'city': city,
            'current_step': 'ready',
        })

    @wrap_model_call
    def wf_config(request: ModelRequest, handler) -> ModelResponse:
        step = request.state.get('current_step', 'ask_city')
        if step == 'ask_city':
            request = request.override(
                system_prompt='你在询问用户的出行城市。用 confirm_city 工具记录城市。',
                tools=[confirm_city],
            )
        else:
            city = request.state.get('city')
            request = request.override(
                system_prompt=f'城市已确认（{city}）。用 get_weather 查询并用一句话回复。',
                tools=[get_weather],
            )
        return handler(request)

    handoff_agent = create_agent(
        model, tools=[confirm_city, get_weather],
        state_schema=WState, middleware=[wf_config],
        checkpointer=InMemorySaver(),
    )
    cfgD = {'configurable': {'thread_id': 'pre-3c-d'}}
    cD1 = CountHandler()
    handoff_agent.invoke({'messages': [{'role': 'user', 'content': '今天天气怎么样？'}]},
                         {**cfgD, 'callbacks': [cD1]})
    print(f"    turn1（未给城市）模型调用: {cD1.calls} 次（ask_city 阶段——询问城市）", flush=True)
    cD2 = CountHandler()
    handoff_agent.invoke({'messages': [{'role': 'user', 'content': '南京'}]},
                         {**cfgD, 'callbacks': [cD2]})
    print(f"    turn2（补充城市）模型调用: {cD2.calls} 次（迁移到 ready → 查询 → 回复）", flush=True)
    cD3 = CountHandler()
    handoff_agent.invoke({'messages': [{'role': 'user', 'content': '再看看天气'}]},
                         {**cfgD, 'callbacks': [cD3]})
    print(f"    turn3（重复请求）模型调用: {cD3.calls} 次（状态保持 ready，直接执行）", flush=True)


# ============================================================
# 主流程
# ============================================================

if __name__ == "__main__":
    print("课 12《Multi-Agent 多智能体》· 全流程实测")
    print(f"环境: Python {os.sys.version.split()[0]} | langchain 1.4.0 / langgraph 1.2.11 | "
          f"模型 qwen3.8-flash")

    section("站一 · 单 agent 极限与拆分")
    exp("1a 静态上下文成本对照", exp_1a)
    exp("1b 单 agent 跨领域工具选择", exp_1b)

    section("站二 · 三大核心模式")
    exp("2a subagents：单体调度", exp_2a)
    exp("2b subagents：并行调度", exp_2b)
    exp("2c subagents：上下文隔离", exp_2c)
    exp("2d handoffs（middleware）：三阶段迁移", exp_2d)
    exp("2e handoffs（subgraph）：销售↔客服", exp_2e)
    exp("2f router：分类-并行-综合", exp_2f)

    section("站三 · 进阶模式与选择")
    exp("3a skills：加载与行为对照", exp_3a)
    exp("3b custom workflow：RAG 流水线", exp_3b)
    exp("3c 四模式调用次数对照", exp_3c)

    print("\n全部实验执行完毕。", flush=True)



