"""课 6 正式实验脚本：Streaming 流式输出（全模式实测）。

设计 5 大板块：
1. 流式 vs 非流式对照（invoke vs stream）
2. stream_mode="updates"（agent 进度）
3. stream_mode="messages"（LLM token 逐字）
4. stream_mode="custom"（自定义信号）
5. stream_events v3（事件流 API，官方推荐新写法）

环境：playground/ uv 管理，Python 3.12 + langchain 1.4.0
默认模型：百炼 qwen3.8-flash（BAILIAN_API_KEY/BAILIAN_BASE_URL）
"""

import os
import time

from dotenv import load_dotenv
from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.tools import tool
from langgraph.config import get_stream_writer

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


# ================= 工具定义 =================

@tool
def get_weather(city: str) -> str:
    """查询城市天气。"""
    return f"{city}：晴天，22°C，湿度 45%"


@tool
def slow_search(query: str) -> str:
    """模拟慢速搜索（用于演示流式进度信号）。"""
    writer = get_stream_writer()
    writer(f"🔍 正在搜索：{query}")
    time.sleep(0.5)
    writer(f"📊 已检索 3 条数据库记录")
    time.sleep(0.3)
    writer(f"✅ 搜索完成")
    return f"关于「{query}」找到 3 条结果：……"


# ================= 1. 流式 vs 非流式对照 =================

section("1. 流式 vs 非流式对照")

agent = create_agent(model, tools=[get_weather])

# 非流式：等全部完成
print("[非流式 invoke] 开始计时…")
t0 = time.time()
result = agent.invoke(
    {"messages": [{"role": "user", "content": "北京天气怎么样？一句话回答。"}]}
)
elapsed = time.time() - t0
print(f"  耗时 {elapsed:.1f}s")
print(f"  终答: {result['messages'][-1].content[:80]}…")

# 流式 updates：逐步输出
print("[流式 stream(updates)] 开始计时…")
t0 = time.time()
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "北京天气怎么样？一句话回答。"}]},
    stream_mode="updates",
    version="v2",
):
    print(f"  [{time.time() - t0:.1f}s] 收到 chunk: {chunk['type']}")
    data = chunk["data"]
    for node_name, node_output in data.items():
        if "messages" in node_output:
            msg = node_output["messages"][-1]
            content = getattr(msg, "content", str(msg))[:60]
            print(f"    节点 {node_name}: {content}")
elapsed = time.time() - t0
print(f"  总耗时 {elapsed:.1f}s")


# ================= 2. stream_mode="updates"（agent 进度） =================蛎

section("2. stream_mode='updates'（agent 进度）")

chunks = []
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "上海天气怎么样？"}]},
    stream_mode="updates",
    version="v2",
):
    chunks.append(chunk)

print(f"共收到 {len(chunks)} 个 chunk")
for i, chunk in enumerate(chunks):
    data = chunk["data"]
    nodes = list(data.keys())
    print(f"  chunk {i + 1}: 节点 {nodes}")
    for node_name, node_output in data.items():
        if "messages" in node_output:
            msg = node_output["messages"][-1]
            msg_type = type(msg).__name__
            has_tool_calls = bool(getattr(msg, "tool_calls", None))
            print(f"    {node_name} → {msg_type} (tool_calls={has_tool_calls})")


# ================= 3. stream_mode="messages"（LLM token 逐字） =================

section("3. stream_mode='messages'（LLM token 逐字）")

print("逐块输出（内容块一行，截断显示）:")
content_n = 0   # 内容块数
empty_n = 0     # 空增量 chunk 数
for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "用一句话介绍北京。"}]},
    stream_mode="messages",
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        node = metadata.get("langgraph_node", "?")
        hit = False
        if hasattr(token, "content_blocks") and token.content_blocks:
            for block in token.content_blocks:
                if block.get("type") == "text":
                    text = block["text"][:40]
                    content_n += 1
                    hit = True
                    if content_n <= 10:
                        print(f"  [{node}] {repr(text)}")
        if not hit:
            empty_n += 1

print(f"  （共 {content_n + empty_n} 个 chunk：内容块 {content_n} 个 + 空增量 {empty_n} 个，空增量已跳过）")


# ================= 4. stream_mode="custom"（自定义信号） =================

section("4. stream_mode='custom'（自定义信号）")

agent_custom = create_agent(model, tools=[slow_search])

print("自定义进度信号:")
for chunk in agent_custom.stream(
    {"messages": [{"role": "user", "content": "搜索一下 LangChain streaming 的最新文档。"}]},
    stream_mode="custom",
    version="v2",
):
    if chunk["type"] == "custom":
        print(f"  📡 {chunk['data']}")


# ================= 5. stream_events v3（事件流 API） =================

section("5. stream_events v3（事件流 API）")

print("v3 事件流（messages 投影）:")
stream = agent.stream_events(
    {"messages": [{"role": "user", "content": "广州天气怎么样？"}]},
    version="v3",
)

for message in stream.messages:
    node = message.node
    print(f"  [{node}] ", end="", flush=True)
    for delta in message.text:
        print(delta, end="", flush=True)
    print()  # 换行分隔每条消息

final_state = stream.output
print(f"\n最终状态 keys: {list(final_state.keys())}")


print("\n（全部实验完成）")
