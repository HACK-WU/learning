"""第 3 课 · 消息体系实验：构造格式、四类消息、工具调用消息流、无状态对话、多模态、序列化。

运行（在 playground 目录内）：

    uv run python lesson-03-messages-lab.py

说明：脚本输出即讲义引用的实测证据，请勿修改后当作新结果引用。
"""

import base64
import os
import struct
import zlib

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage
from langchain_core.load import dumpd, load

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


def brief(block):
    """打印内容块时把 base64 数据折叠成长度提示。"""
    b = dict(block)
    if "base64" in b:
        b["base64"] = f"<{len(b['base64'])} 个字符的 base64>"
    return b


# ================= 1. 三种构造格式 =================
section("1a. 字符串快捷（单次请求）")
r = model.invoke("用一句话向我问好。")
print(f"返回类型: {type(r).__name__} | 内容: {r.content[:60]}")

section("1b. 消息对象列表（含 System）")
r = model.invoke([
    SystemMessage("你是一位唐诗专家，回答保持简短。"),
    HumanMessage("用一句诗描述春天。"),
])
print(f"返回类型: {type(r).__name__} | 内容: {r.content[:60]}")

section("1c. 字典格式（OpenAI 风格）")
r = model.invoke([
    {"role": "system", "content": "你是一位唐诗专家，回答保持简短。"},
    {"role": "user", "content": "用一句诗描述夏天。"},
])
print(f"返回类型: {type(r).__name__} | 内容: {r.content[:60]}")

# ================= 2. 四类消息构造 =================
section("2. 四类消息对象（构造与关键字段）")
sys_msg = SystemMessage("你是一个严谨的客服助手。")
hum_msg = HumanMessage("北京今天天气怎么样？", name="alice", id="msg_h1")
ai_msg = AIMessage(
    content="",
    tool_calls=[{"name": "get_weather", "args": {"city": "北京"}, "id": "call_demo_1"}],
)
tool_msg = ToolMessage(content="北京：晴，26℃。", tool_call_id="call_demo_1", name="get_weather")

print(f"[{type(sys_msg).__name__}] content={sys_msg.content!r}")
print(f"[{type(hum_msg).__name__}] content={hum_msg.content!r} | name={hum_msg.name!r} | id={hum_msg.id!r}")
print(f"[{type(ai_msg).__name__}] content={ai_msg.content!r}")
print(f"    tool_calls={ai_msg.tool_calls}")
print(f"[{type(tool_msg).__name__}] content={tool_msg.content!r} | tool_call_id={tool_msg.tool_call_id!r} | name={tool_msg.name!r}")

# ================= 3. 工具调用消息流 =================
section("3. 工具调用消息流（真实模型）")


def get_weather(city: str) -> str:
    """查询指定城市的天气。"""
    return f"{city}：晴，26℃，微风。"


model_wt = model.bind_tools([get_weather])
hum = HumanMessage("北京今天天气怎么样？")

r1 = model_wt.invoke([hum])
tc = r1.tool_calls[0]
print(f"第 1 轮 AI 消息: content={r1.content!r}")
print(f"  tool_calls: name={tc['name']!r} | args={tc['args']} | id={tc['id']!r}")
print(f"  该消息的 content_blocks: {r1.content_blocks}")

tool_result = get_weather(**tc["args"])
tm = ToolMessage(content=tool_result, tool_call_id=tc["id"], name=tc["name"])
print(f"Tool 消息: content={tm.content!r} | tool_call_id={tm.tool_call_id!r}")

r2 = model_wt.invoke([hum, r1, tm])
print(f"第 2 轮 AI 消息: {r2.content[:80]}")

section("3b. 完整消息流一览")
for i, m in enumerate([hum, r1, tm, r2], 1):
    note = ""
    if getattr(m, "tool_calls", None):
        note = f" → 请求调用 {m.tool_calls[0]['name']}（id={m.tool_calls[0]['id']}）"
    if isinstance(m, ToolMessage):
        note = f" → 回执（id={m.tool_call_id}）"
    text = m.content if isinstance(m.content, str) else "[内容块列表]"
    print(f"  {i}. [{type(m).__name__}] {text[:50]!r}{note}")

# ================= 4. 消息属性 =================
section("4. 消息对象的属性（以第 2 轮 AI 消息为例）")
print(f"text: {r2.text[:50]!r}")
print(f"content 类型: {type(r2.content).__name__}")
print(f"content_blocks: {r2.content_blocks}")
print(f"id: {r2.id!r}")
print(f"usage_metadata: {r2.usage_metadata}")
rm = r2.response_metadata
print(f"response_metadata 键: {list(rm.keys())}")
print(f"  finish_reason={rm.get('finish_reason')!r} | model_name={rm.get('model_name')!r}")

# ================= 5. 无状态实验 =================
section("5. 『消息列表就是模型的全部输入』——无状态实验")
q1 = HumanMessage("请记住：我的幸运数字是 42。只回复：好的")
r_1 = model.invoke([q1])
print(f"第 1 轮（告知）: {r_1.content.strip()[:40]!r}")

q2 = HumanMessage("我的幸运数字是多少？")
r_no = model.invoke([q2])
print(f"第 2 轮（不携带历史）: {r_no.content.strip()[:90]!r}")

r_yes = model.invoke([q1, r_1, q2])
print(f"第 2 轮（携带历史）: {r_yes.content.strip()[:90]!r}")

# ================= 6. 多模态内容块 =================
section("6. 多模态内容块（标准格式构造）")
png_b64 = base64.b64encode(make_red_png()).decode()
msg = HumanMessage(content_blocks=[
    {"type": "text", "text": "这张图是什么颜色？只回答颜色名。"},
    {"type": "image", "base64": png_b64, "mime_type": "image/png"},
])
print("构造后的 .content（供应商原生格式视图）:")
if isinstance(msg.content, str):
    print(f"  （字符串）{msg.content[:80]!r}")
else:
    for b in msg.content:
        print(f"  {brief(b)}")
print("构造后的 .content_blocks（标准格式视图）:")
for b in msg.content_blocks:
    print(f"  {brief(b)}")

resp = model.invoke([msg])
print(f"模型回答: {resp.content.strip()!r}")
print(f"响应的 content_blocks: {resp.content_blocks}")

# ================= 7. 序列化 =================
section("7. 序列化与恢复")
serialized_h = dumpd(hum)
print(f"dumpd(HumanMessage) 前 200 字符: {str(serialized_h)[:200]}")
restored_h = load(serialized_h)
print(f"load 恢复: {type(restored_h).__name__} | content={str(restored_h.content)[:40]!r}")

serialized_ai = dumpd(r1)
restored_ai = load(serialized_ai)
print(f"AI 消息恢复后 tool_calls 保留: {restored_ai.tool_calls}")
