"""第 3 课 · 补充实验：消息格式的边界与坑。

运行（在 playground 目录内）：

    uv run python lesson-03-messages-lab2.py

说明：采集"老教程写法""工具回执配对""懒解析"等边界场景的真实行为，
输出即讲义引用的实测证据。为控制演示时长，模型已设置 max_retries=2。
"""

import os

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, HumanMessage, ToolMessage

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


section("A. 旧教程写法：字典里用 role='human'（旧版 LangChain 风格）")
try:
    r = model.invoke([{"role": "human", "content": "你好"}])
    print(f"未报错 | 回答: {r.content[:50]}")
except Exception as e:
    print(f"异常类型: {type(e).__name__}")
    print(f"消息摘要: {str(e)[:300]}")
    print("--- 改为 role='user' 再试一次 ---")
    r = model.invoke([{"role": "user", "content": "你好"}])
    print(f"成功 | 回答: {r.content[:50]}")


def get_weather(city: str) -> str:
    """查询指定城市的天气。"""
    return f"{city}：晴，26℃，微风。"


section("B. 工具回执配对：tool_call_id 不匹配")
model_wt = model.bind_tools([get_weather])
hum = HumanMessage("北京今天天气怎么样？")
r1 = model_wt.invoke([hum])
tc = r1.tool_calls[0]
print(f"AI 请求的 id: {tc['id']!r}")
wrong = ToolMessage(content="北京：晴。", tool_call_id="call_WRONG_123", name="get_weather")
try:
    r = model_wt.invoke([hum, r1, wrong])
    print(f"未报错 | 回答: {str(r.content)[:80]}")
except Exception as e:
    print(f"异常类型: {type(e).__name__}")
    print(f"消息摘要: {str(e)[:300]}")

section("C. 缺少工具回执（只有请求，没有结果）")
try:
    r = model_wt.invoke([hum, r1])
    print(f"未报错 | 回答: {str(r.content)[:80]}")
except Exception as e:
    print(f"异常类型: {type(e).__name__}")
    print(f"消息摘要: {str(e)[:300]}")

section("D. ToolMessage 不传 name 能否构造")
try:
    tm = ToolMessage(content="测试内容", tool_call_id="call_x")
    print(f"构造成功 | name={tm.name!r}")
except Exception as e:
    print(f"异常类型: {type(e).__name__}")
    print(f"消息摘要: {str(e)[:200]}")

section("E. 懒解析：用供应商原生格式构造，content_blocks 自动标准化（离线演示）")
message = AIMessage(
    content=[
        {"type": "thinking", "thinking": "先想一下……", "signature": "sig_demo"},
        {"type": "text", "text": "最终回答"},
    ],
    response_metadata={"model_provider": "anthropic"},
)
print("content 原样类型:", [b["type"] for b in message.content])
print("content_blocks 标准化:", message.content_blocks)

section("F. 字典角色名单查证（离线，无 API 调用）")
from langchain_core.messages import convert_to_messages

for role in ("system", "user", "assistant", "human", "ai", "foo"):
    try:
        m = convert_to_messages([{"role": role, "content": "x"}])
        print(f"{role!r:12} -> {type(m[0]).__name__}")
    except Exception as e:
        print(f"{role!r:12} -> {type(e).__name__}: {str(e)[:130]}")

msgs = convert_to_messages([{"role": "tool", "content": "回执", "tool_call_id": "call_1"}])
print(f"{'tool':12} -> {type(msgs[0]).__name__}（需带 tool_call_id）")
