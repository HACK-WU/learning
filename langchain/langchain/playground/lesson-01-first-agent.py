"""第 1 课 · 第一个 Agent：让"只会聊天"的模型学会用工具。

运行（在 playground 目录内）：

    uv run python lesson-01-first-agent.py

预期：模型先"决定"调用 get_weather 工具，拿到结果后组织成自然语言回答。
"""

import os

from dotenv import load_dotenv
from langchain.agents import create_agent
from langchain.chat_models import init_chat_model

load_dotenv()


def get_weather(city: str) -> str:
    """查询指定城市的天气。"""
    return f"{city}：晴，26℃，微风。"


model = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=os.environ["BAILIAN_API_KEY"],
    base_url=os.environ["BAILIAN_BASE_URL"],
)

agent = create_agent(
    model=model,
    tools=[get_weather],
    system_prompt="你是一个乐于助人的助手，回答简洁。",
)

result = agent.invoke(
    {"messages": [{"role": "user", "content": "北京今天天气怎么样？"}]}
)

print("========== 完整消息流 ==========")
for i, message in enumerate(result["messages"], 1):
    kind = type(message).__name__
    content = message.content if isinstance(message.content, str) else str(message.content)
    tool_calls = getattr(message, "tool_calls", None)
    suffix = ""
    if tool_calls:
        suffix = "  [tool_calls: " + ", ".join(tc["name"] for tc in tool_calls) + "]"
    print(f"{i}. [{kind}]{suffix} {content[:150]}")

print()
print("========== 最终回复 ==========")
print(result["messages"][-1].content)
