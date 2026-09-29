# -*- coding: utf-8 -*-
"""课 12 补跑：3b 检索修正 / 2e 单方向交接 / 2d state 观测 / 3a 完整输出 / 3c-B 细节 / 1b 工具过载测试。

补跑清单：
  A. 3b 修正版：RAG pipeline 用切分后的知识库 + k=3（首跑未命中答案块）
  B. 3c-B 细节：skills 模式 turn2 消息路径（确认 3 次调用的来源）
  C. 2e 单方向：纯技术问题的完整交接链路（首跑为双问题双向 ping-pong）
  D. 2d state 观测：turn1 结束后完整 state keys（验证类默认值不自动写入 state）
  E. 3a 完整输出：技能加载后 SQL 全文（验证技能三条规则的执行情况）
  F. 1b 工具过载：16 个工具下的选择行为（8 真实 + 8 近似/噪声）
"""
import os
import time
from typing import Annotated, Literal, TypedDict

from dotenv import load_dotenv

load_dotenv(r'D:/projects/learning/langchain/langchain/playground/.env')

import operator

from langchain.agents import AgentState, create_agent
from langchain.agents.middleware import ModelRequest, ModelResponse, wrap_model_call
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, ToolMessage
from langchain.tools import ToolRuntime, tool
from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.documents import Document
from langchain_core.vectorstores import InMemoryVectorStore
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.types import Command
from typing_extensions import NotRequired

model = init_chat_model(
    "qwen3.8-flash", model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
    max_retries=2, timeout=60,
)


class CountHandler(BaseCallbackHandler):
    def __init__(self):
        self.calls = 0

    def on_chat_model_start(self, serialized, messages, **kwargs):
        self.calls += 1


def section(title: str) -> None:
    print(f"\n{'=' * 16} {title} {'=' * 16}", flush=True)


def brief(content, limit: int = 140) -> str:
    text = str(content) if content is not None else ""
    return " ".join(text.split())[:limit]


def show_chain(msgs, limit: int = 90) -> None:
    for m in msgs:
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


# 基础工具（与主脚本一致）
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


# ============================================================
# 补跑 A：3b 修正版（切分 + k=3）
# ============================================================

def fix_A():
    from pathlib import Path
    emb = OpenAIEmbeddings(
        model=os.environ['SILICONFLOW_EMBEDDING_MODEL'],
        api_key=os.environ['SILICONFLOW_API_KEY'],
        base_url=os.environ['SILICONFLOW_BASE_URL'],
        check_embedding_ctx_length=False,
    )
    kb_dir = Path(r'D:/projects/learning/langchain/langchain/playground/kb')
    docs = [Document(page_content=p.read_text(encoding='utf-8'), metadata={'source': p.name})
            for p in sorted(kb_dir.glob('*.md'))]
    sp = RecursiveCharacterTextSplitter(chunk_size=300, chunk_overlap=60)
    chunks = sp.split_documents(docs)
    store = InMemoryVectorStore(emb)
    store.add_documents(chunks)
    retriever = store.as_retriever(search_kwargs={'k': 3})
    print(f"  [准备] 5 份文档切成 {len(chunks)} 块入库（chunk_size=300/overlap=60）", flush=True)

    class WFState(TypedDict):
        question: str
        rewritten: str
        docs: list[str]
        sources: list[str]
        answer: str

    def node_rewrite(state: WFState) -> dict:
        r = model.invoke('把下面的问题改写成适合检索的关键词（一行，不加解释）：\n' + state['question'])
        rw = r.content.strip()
        print(f"    [rewrite] '{state['question']}' -> '{rw[:60]}'", flush=True)
        return {'rewritten': rw}

    def node_retrieve(state: WFState) -> dict:
        hits = retriever.invoke(state['rewritten'])
        texts = [f'[{d.metadata["source"]}] {d.page_content}' for d in hits]
        print(f"    [retrieve] 命中 {len(hits)} 块: {[d.metadata['source'] for d in hits]}", flush=True)
        return {'docs': texts, 'sources': [d.metadata['source'] for d in hits]}

    answer_agent = create_agent(
        model, tools=[get_weather],
        system_prompt='你是企业助手。基于给定资料回答问题并注明来源；资料不足时如实说明。',
    )

    def node_agent(state: WFState) -> dict:
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
    print(f"  回答: {brief(r['answer'], 320)}", flush=True)


# ============================================================
# 补跑 B：3c-B skills turn2 细节
# ============================================================

def fix_B():
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
    r1_msgs = None
    c1 = CountHandler()
    r1 = skill_agent.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                            {'callbacks': [c1]})
    r1_msgs = r1['messages']
    print(f"  turn1 模型调用: {c1.calls} 次", flush=True)
    print("  turn1 工具轨迹：", flush=True)
    for m in r1_msgs:
        if getattr(m, 'tool_calls', None):
            for tc in m.tool_calls:
                print(f"    -> {tc['name']}", flush=True)
    print(flush=True)
    c2 = CountHandler()
    r2 = skill_agent.invoke({'messages': [{'role': 'user', 'content': '南京今天天气怎么样？'}]},
                            {'callbacks': [c2]})
    print(f"  turn2 模型调用: {c2.calls} 次", flush=True)
    print("  turn2 新增消息（工具轨迹）：", flush=True)
    for m in r2['messages'][len(r1_msgs):]:
        t = getattr(m, 'type', '?')
        if t == 'ai' and getattr(m, 'tool_calls', None):
            for tc in m.tool_calls:
                print(f"    [ai] -> tool: {tc['name']}", flush=True)
        elif t == 'tool':
            print(f"    [tool]: {brief(m.content, 70)}", flush=True)
        elif t == 'ai':
            print(f"    [ai]: {brief(m.content, 110)}", flush=True)
        else:
            print(f"    [{t}]: {brief(m.content, 60)}", flush=True)


# ============================================================
# 补跑 C：2e 单方向交接（纯技术问题）
# ============================================================

def fix_C():
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

    gateway_sales = create_agent(
        model, tools=[transfer_to_support],
        system_prompt='你是销售代理。若客户问技术问题，调用 transfer_to_support 转交。',
    )
    gateway_support = create_agent(
        model, tools=[],
        system_prompt='你是技术支持代理，负责技术问题排查。给出排查步骤。',
    )

    def call_sales(state):
        return gateway_sales.invoke(state)

    def call_support(state):
        return gateway_support.invoke(state)

    def route_after(state):
        msgs = state.get('messages', [])
        if msgs:
            last = msgs[-1]
            if isinstance(last, AIMessage) and not last.tool_calls:
                return '__end__'
        return state.get('active_agent') or 'sales_agent'

    def route_initial(state):
        return state.get('active_agent') or 'sales_agent'

    b = StateGraph(MultiAgentState)
    b.add_node('sales_agent', call_sales)
    b.add_node('support_agent', call_support)
    b.add_conditional_edges(START, route_initial, ['sales_agent', 'support_agent'])
    b.add_conditional_edges('sales_agent', route_after, ['sales_agent', 'support_agent', END])
    b.add_conditional_edges('support_agent', route_after, ['sales_agent', 'support_agent', END])
    g = b.compile()
    q = '我的设备连不上网，怎么修？'
    print(f"  问题: {q}", flush=True)
    r = g.invoke({'messages': [{'role': 'user', 'content': q}]})
    print("  消息路径：", flush=True)
    show_chain(r['messages'], limit=110)
    print(f"  最终 active_agent: {r.get('active_agent')}", flush=True)


# ============================================================
# 补跑 D：2d state keys 观测
# ============================================================

def fix_D():
    class SupportState(AgentState):
        current_step: str = 'triage'
        device: str | None = None

    @tool
    def record_warranty(device: str, runtime: ToolRuntime[None, SupportState]) -> Command:
        """记录设备型号，进入诊断阶段。"""
        return Command(update={
            'messages': [ToolMessage(content=f'已记录：{device}', tool_call_id=runtime.tool_call_id)],
            'device': device,
            'current_step': 'diagnose',
        })

    @wrap_model_call
    def cfg_mw(request: ModelRequest, handler) -> ModelResponse:
        step = request.state.get('current_step', 'triage')
        print(f"      [中间件] fallback 读取 step={step} | state keys={sorted(request.state.keys())}", flush=True)
        return handler(request)

    agent = create_agent(
        model, tools=[record_warranty],
        state_schema=SupportState, middleware=[cfg_mw],
        checkpointer=InMemorySaver(),
    )
    cfg = {'configurable': {'thread_id': 'fix-d'}}
    print("  [turn1]（模型不调工具，直接回复的场景）：", flush=True)
    r = agent.invoke({'messages': [{'role': 'user', 'content': '你好，我想咨询一下。'}]}, cfg)
    print(f"    turn1 输出 state 的键: {sorted(k for k in r.keys() if not k.startswith('__'))}", flush=True)
    print(f"    turn1 r.get('current_step') = {r.get('current_step')!r}（注意：类默认值未自动写入）", flush=True)
    print(flush=True)
    print("  [turn2]（模型调用工具记录后）：", flush=True)
    r2 = agent.invoke({'messages': [{'role': 'user', 'content': '设备是华为 P60。'}]}, cfg)
    print(f"    turn2 r.get('current_step') = {r2.get('current_step')!r}（工具更新后写入）", flush=True)


# ============================================================
# 补跑 E：3a 完整 SQL 输出
# ============================================================

def fix_E():
    SKILLS = {
        'sql_expert': (
            '你是 SQL 专家。写查询时必须遵守：\n'
            '1) 禁止 SELECT *，必须显式列出字段；\n'
            '2) 时间过滤用 WHERE，不要全表扫描；\n'
            '3) 输出结构：先给 SQL，再给一句性能提示。'
        ),
    }

    @tool
    def load_skill(skill_name: str) -> str:
        """加载专业技能包。可用技能：sql_expert。"""
        return f'[技能已加载: {skill_name}]\n{SKILLS[skill_name]}'

    skill_agent = create_agent(
        model, tools=[load_skill],
        system_prompt='你是通用助手。任务涉及 SQL 时，必须先调用 load_skill 加载 sql_expert 技能，'
                      '再按技能要求完成（注意三条规则都要执行）。',
    )
    q = '帮我写一条 SQL：查询用户表里最近 7 天注册的用户。'
    r = skill_agent.invoke({'messages': [{'role': 'user', 'content': q}]})
    final = r['messages'][-1].content
    print(f"  完整回答（{len(str(final))} 字符）：", flush=True)
    print('  ' + '-' * 60, flush=True)
    for line in str(final).splitlines():
        print(f"  | {line}", flush=True)
    print('  ' + '-' * 60, flush=True)
    has_star = 'SELECT *' in str(final)
    has_fields = 'id' in str(final) and 'created_at' in str(final)
    print(f"  规则核查: 含 'SELECT *' = {has_star}（技能要求禁止）| 显式字段 = {has_fields}", flush=True)


# ============================================================
# 补跑 F：1b 工具过载（16 个工具）
# ============================================================

def fix_F():
    from langchain_core.tools import StructuredTool

    def make_tool(name: str, desc: str, ret: str):
        def fn(query: str = '') -> str:
            return ret
        return StructuredTool.from_function(func=fn, name=name, description=desc)

    extra_tools = [
        make_tool('weather_forecast', '查询未来 7 天天气预报。', '未来 7 天：晴转多云'),
        make_tool('weather_history', '查询历史天气记录。', '上月同日：多云 19°C'),
        make_tool('weather_air', '查询城市空气质量指数。', 'AQI 62，良'),
        make_tool('stock_news', '查询股票相关新闻。', '最新新闻：3 条'),
        make_tool('stock_dividend', '查询股票分红记录。', '近 5 年分红记录：4 次'),
        make_tool('exchange_rate', '查询实时汇率。', 'USD/CNY = 7.12'),
        make_tool('sql_format', '格式化 SQL 语句。', '格式化完成'),
        make_tool('sql_index_advice', '给出索引建议。', '建议为 user_id 建索引'),
        make_tool('send_email', '发送邮件。', '已发送'),
        make_tool('create_event', '创建日历事件。', '已创建'),
        make_tool('translate_text', '翻译文本。', '已翻译'),
        make_tool('search_docs', '搜索内部文档。', '找到 3 篇'),
    ]
    big_tools = [get_weather, get_stock, convert_currency, explain_sql] + extra_tools
    print(f"  工具总数: {len(big_tools)}（4 真实 + 8 近似领域 + 4 其他领域）", flush=True)
    big_agent = create_agent(
        model, tools=big_tools,
        system_prompt='你是全能助手。根据用户问题选择最合适的工具。',
    )
    counter = CountHandler()
    q = '帮我看看空气质量怎么样，城市是上海。'
    print(f"  问题（测试近似工具选择）: {q}", flush=True)
    r = big_agent.invoke({'messages': [{'role': 'user', 'content': q}]}, {'callbacks': [counter]})
    print(f"  模型调用: {counter.calls} 次", flush=True)
    for m in r['messages']:
        if getattr(m, 'tool_calls', None):
            for tc in m.tool_calls:
                print(f"    -> 选中工具: {tc['name']}({brief(tc['args'], 50)})", flush=True)
        elif getattr(m, 'type', '') == 'ai' and m.content:
            print(f"    ai: {brief(m.content, 110)}", flush=True)


if __name__ == '__main__':
    print("课 12 补跑脚本")
    section("补跑 A：3b 修正（切分 + k=3）")
    t0 = time.time()
    try:
        fix_A()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [耗时 {time.time() - t0:.1f}s]", flush=True)

    section("补跑 B：3c-B skills turn2 细节")
    t0 = time.time()
    try:
        fix_B()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [耗时 {time.time() - t0:.1f}s]", flush=True)

    section("补跑 C：2e 单方向交接")
    t0 = time.time()
    try:
        fix_C()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [耗时 {time.time() - t0:.1f}s]", flush=True)

    section("补跑 D：2d state keys 观测")
    t0 = time.time()
    try:
        fix_D()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [耗时 {time.time() - t0:.1f}s]", flush=True)

    section("补跑 E：3a 完整 SQL 输出")
    t0 = time.time()
    try:
        fix_E()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [耗时 {time.time() - t0:.1f}s]", flush=True)

    section("补跑 F：1b 工具过载（16 工具）")
    t0 = time.time()
    try:
        fix_F()
    except Exception as e:
        print(f"  [失败] {type(e).__name__}: {e}", flush=True)
    print(f"  [耗时 {time.time() - t0:.1f}s]", flush=True)

    print("\n补跑完毕。", flush=True)
