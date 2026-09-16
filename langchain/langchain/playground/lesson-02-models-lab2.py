"""第 2 课 · 模型层补充实验：推理模型的 token 预算、流式内容块、reasoning_effort 传参。

运行（在 playground 目录内）：

    uv run python lesson-02-models-lab2.py

说明：本脚本是主实验（lesson-02-models-lab.py）的补充对照，输出即讲义引用的实测证据。
"""

import os

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model

load_dotenv()

API_KEY = os.environ["BAILIAN_API_KEY"]
BASE_URL = os.environ["BAILIAN_BASE_URL"]


def section(title: str) -> None:
    print(f"\n{'=' * 18} {title} {'=' * 18}")


def make_model(**kwargs):
    return init_chat_model(
        "qwen3.8-flash",
        model_provider="openai",
        api_key=API_KEY,
        base_url=BASE_URL,
        **kwargs,
    )


section("A. max_tokens 对照：24（主实验） vs 100")
m100 = make_model(max_tokens=100)
r = m100.invoke("请用尽可能长的篇幅介绍杭州。")
print(f"max_tokens=100 时输出前 120 字: {r.content[:120]!r}")
print(f"finish_reason: {r.response_metadata.get('finish_reason')}")
print(f"usage: {r.usage_metadata}")

section("B. 流式时内容块类型序列")
kinds = []
for chunk in make_model().stream("一个笼子里有鸡和兔共 8 只，脚共 26 只，鸡兔各几只？"):
    for block in chunk.content_blocks:
        kinds.append(block["type"])
print(f"全部内容块类型（去重按序）: {sorted(set(kinds))}")

section("C. reasoning_effort 传参（标准参数，看该模型是否支持）")
try:
    r = make_model().invoke(
        "1 加到 10 等于多少？",
        reasoning_effort="high",
    )
    print(f"传参成功，回答: {r.content[:60]!r}")
    print(f"usage: {r.usage_metadata}")
except Exception as e:
    print(f"异常类型: {type(e).__name__}")
    print(f"消息摘要: {str(e)[:200]}")

section("D. max_tokens=500 对照（正文是否出现）")
r = make_model(max_tokens=500).invoke("请用尽可能长的篇幅介绍杭州。")
print(f"输出前 150 字: {r.content[:150]!r}")
print(f"finish_reason: {r.response_metadata.get('finish_reason')}")
print(f"usage: {r.usage_metadata}")

section("E. 异常类型与 LangChain 标准异常基类的关系")
from langchain_core.exceptions import ModelAuthenticationError

try:
    bad = init_chat_model(
        "qwen3.8-flash",
        model_provider="openai",
        api_key="sk-invalid-key-for-demo",
        base_url=BASE_URL,
        max_retries=1,
        timeout=15,
    )
    bad.invoke("你好")
except Exception as e:
    print(f"实际异常类型: {type(e).__name__}")
    print(f"MRO: {' -> '.join(c.__name__ for c in type(e).__mro__)}")
    print(f"isinstance(e, ModelAuthenticationError): {isinstance(e, ModelAuthenticationError)}")
