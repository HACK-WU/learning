"""第 2 课 · 模型层实验：初始化、调用方式、参数、能力档案、多模态、推理内容。

运行（在 playground 目录内）：

    uv run python lesson-02-models-lab.py

说明：脚本中的输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import base64
import os
import struct
import time
import zlib

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model
from langchain_openai import ChatOpenAI

load_dotenv()

API_KEY = os.environ["BAILIAN_API_KEY"]
BASE_URL = os.environ["BAILIAN_BASE_URL"]


def section(title: str) -> None:
    print(f"\n{'=' * 18} {title} {'=' * 18}")


def make_red_png(size: int = 32) -> bytes:
    """生成一张纯红色 PNG（标准库实现，不引入额外依赖）。"""
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * size for _ in range(size))

    def chunk(tag: bytes, data: bytes) -> bytes:
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


# ================= 1. 两种初始化方式 =================
section("1. 两种初始化方式")
model_a = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=API_KEY,
    base_url=BASE_URL,
)
model_b = ChatOpenAI(model="qwen3.8-flash", api_key=API_KEY, base_url=BASE_URL)
print(f"init_chat_model 返回类型: {type(model_a).__name__}")
print(f"Model Class  返回类型: {type(model_b).__name__}")

# ================= 2. 三种调用方式 =================
section("2a. invoke（单次）")
t0 = time.time()
resp = model_a.invoke("用一句话解释什么是内存泄漏。")
invoke_elapsed = time.time() - t0
print(f"返回类型: {type(resp).__name__}")
print(f"内容: {resp.content}")
print(f"usage_metadata: {resp.usage_metadata}")
print(f"耗时: {invoke_elapsed:.2f}s（该值将在 batch 对比中使用）")

section("2b. stream（流式）")
chunks = 0
full = None
shown = 0
t0 = time.time()
for chunk in model_a.stream("用一句话解释什么是死锁。"):
    chunks += 1
    full = chunk if full is None else full + chunk
    if chunk.text and shown < 5:
        shown += 1
        print(f"非空文本 chunk #{shown}: {chunk.text!r}")
print(f"共收到 {chunks} 个 chunk，耗时 {time.time() - t0:.2f}s")
print(f"累加后类型: {type(full).__name__}")
print(f"累加结果: {full.text}")

section("2c. batch（批量）")
t0 = time.time()
results = model_a.batch(
    [
        "1+1=? 只回答数字",
        "2+2=? 只回答数字",
        "3+3=? 只回答数字",
    ]
)
batch_elapsed = time.time() - t0
print(f"3 条并发 batch 总耗时: {batch_elapsed:.2f}s（单条 invoke 耗时: {invoke_elapsed:.2f}s）")
for i, r in enumerate(results, 1):
    print(f"  {i}. {r.content.strip()}")

# ================= 3. 参数 =================
section("3a. max_tokens 限制输出长度")
long_model = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=API_KEY,
    base_url=BASE_URL,
    max_tokens=24,
)
truncated = long_model.invoke("请用尽可能长的篇幅介绍杭州。")
print(f"max_tokens=24 时输出: {truncated.content!r}")
print(f"finish_reason: {truncated.response_metadata.get('finish_reason')}")

section("3b. temperature 调用时传入（同一问题两次）")
for i in (1, 2):
    r = model_a.invoke("给一种动物的名字（只回一个词）。", temperature=0)
    print(f"  temperature=0 第 {i} 次: {r.content.strip()!r}")

section("3c. 换一个平台：同一份代码，配置切换（DeepSeek 备用链路）")
ds_model = init_chat_model(
    "deepseek-flash",
    model_provider="openai",
    api_key=os.environ["DEEPSEEK_API_KEY"],
    base_url=os.environ["DEEPSEEK_BASE_URL"],
)
ds_resp = ds_model.invoke("用一句话介绍你自己。")
print(f"DeepSeek deepseek-flash: {ds_resp.content[:100]}")

# ================= 4. 模型能力档案（profile） =================
section("4. 模型能力档案（profile）")
print(f"qwen3.8-flash  profile: {model_a.profile}")
print(f"deepseek-flash profile: {ds_model.profile}")
custom = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    api_key=API_KEY,
    base_url=BASE_URL,
    profile={"max_input_tokens": 100_000, "tool_calling": True},
)
print(f"手动覆写 profile 后: {custom.profile}")

# ================= 5. 多模态输入 =================
section("5. 多模态：发送一张红色图片")
png_b64 = base64.b64encode(make_red_png()).decode()
message = {
    "role": "user",
    "content": [
        {"type": "text", "text": "这张图是什么颜色？只回答颜色名。"},
        {
            "type": "image_url",
            "image_url": {"url": f"data:image/png;base64,{png_b64}"},
        },
    ],
}
vision = model_a.invoke([message])
print(f"图片识别回答: {vision.content.strip()}")

# ================= 6. 推理内容（reasoning） =================
section("6. 推理模型的内容特性")
resp = model_a.invoke("一个笼子里有鸡和兔共 8 只，脚共 26 只。鸡和兔各几只？")
print(f"内容块类型: {[b['type'] for b in resp.content_blocks]}")
reasoning = [b for b in resp.content_blocks if b["type"] == "reasoning"]
if reasoning:
    text = " ".join(str(b.get("reasoning", "")) for b in reasoning)
    print(f"reasoning 块数: {len(reasoning)}，摘要: {text[:120]}")
else:
    print("（未返回 reasoning 内容块）")
print(f"最终回答: {resp.content[:120]}")
print(f"usage: {resp.usage_metadata}")
