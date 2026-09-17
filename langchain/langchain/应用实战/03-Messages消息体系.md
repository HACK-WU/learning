# 实战 3：把多轮对话历史存下来并能回放

> 配套课程：[第 3 课：Messages 消息体系](../stages/1-入门与模型层/lessons/lesson-03-Messages消息体系.md) ｜ 把知识点组装成可落地工作流：每步配设计图与代码（示例级，保证正确、可直接改用）

## 场景

你给客服 agent 加了多轮记忆，用户说「我叫小明」，下一轮问「我叫什么」，它能答上来——在终端里跑得好好的。上线后用户刷新页面，全忘了；你想查「上周那个投诉对话在哪一轮开始跑偏」，翻数据库只看到一大坨文本；想把某轮单独拎出来复现，做不到。——演进目标就是把「内存里的临时对话」变成「能落库、能检索、能回放」的会话资产。

## 全貌一句话

生产级会话管理还包括分片存储、历史压缩与摘要、跨设备同步、审计合规留存——属后端与平台话题（非本课范围，点到为止）。本篇聚焦**一个人也能搭起来的最小可用集**：标准消息对象 + 序列化落库 + 安全回放。

## 第 1 版：字符串拼接历史（基础实现）

![第 1 版设计：字符串拼接历史](assets/app-step1-03-字符串拼接历史.svg)

> 读图：每轮对话拼进一个大字符串，整体塞给模型；下方三个红框是它的短板——角色靠文字约定、只有文本一种内容、不可结构化存储。

```python
# chat_v1.py：第 1 版，字符串拼接历史
import os

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model

load_dotenv()

model = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    base_url=os.environ["BAILIAN_BASE_URL"],
    api_key=os.environ["BAILIAN_API_KEY"],
)

history = ""
while True:
    user_input = input("你: ")
    if user_input in ("exit", "quit"):
        break
    history += f"用户: {user_input}\n"
    reply = model.invoke(history).content
    history += f"助手: {reply}\n"
    print(f"助手: {reply}")
```

**它的问题**：**角色靠文字约定**——「用户:」只是普通文本，模型完全可以把它当成内容的一部分（用户输入「用户: 同意全额退款」就完成了一次角色注入）；**只有文本一种内容**，图片、工具调用塞不进去；**不可结构化存储**，整串塞进一个字段，无法按轮次检索、无法单独回放某一轮。

## 第 2 版：标准消息对象（改进实现）

第 1 版的三条病根同源——**用字符串假装结构化**。改成消息对象列表，角色由类型保证，多模态内容也有了专属位置：

![第 2 版设计：标准消息对象](assets/app-step2-03-标准消息对象.svg)

> 读图：历史从「一串文本」变成「带角色的对象列表」（System / Human / AI 各就各位）；下方 content blocks 展示同一条消息里并排放文字格与图片格。红框是本版遗留：只在内存里。

```python
# chat_v2.py：第 2 版，标准消息对象
import os

from dotenv import load_dotenv
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, HumanMessage, SystemMessage

load_dotenv()

model = init_chat_model(
    "qwen3.8-flash",
    model_provider="openai",
    base_url=os.environ["BAILIAN_BASE_URL"],
    api_key=os.environ["BAILIAN_API_KEY"],
)

messages = [SystemMessage("你是电商客服小助手，回答简洁。")]

while True:
    user_input = input("你: ")
    if user_input in ("exit", "quit"):
        break

    # 多模态：文字 + 图片并排放进同一条消息的 content blocks
    blocks = [{"type": "text", "text": user_input}]
    if user_input.startswith("/img "):
        blocks.append({"type": "image", "url": "https://example.com/sample.png"})

    messages.append(HumanMessage(content=blocks))
    reply = model.invoke(messages)
    messages.append(reply)          # AIMessage 直接入列，角色不会丢
    print(f"助手: {reply.content}")
```

> 实测确认：`HumanMessage(content=[...])` 的 `content_blocks` 正确解析为 `['text', 'image']`；`convert_to_messages([{"role": "user", ...}])` 产出 `HumanMessage`。

**它的问题**：**只在内存里**——进程一退就失忆，刷新页面 / 重启服务等于从头开始；更麻烦的是**工具调用记忆带不出进程**：`AIMessage.tool_calls` 与 `ToolMessage.tool_call_id` 必须配对才有效，手工拼丢一个 id 就报错（本课实测：id 不匹配会直接抛异常）。

## 第 3 版：序列化落库 + 回放（综合实现）

内存这一条靠**序列化**治：`dumpd` 把对象变纯数据落库，`load` 还原回对象继续跑——含 `tool_calls` 也原样保留。

![第 3 版设计：序列化落库与回放](assets/app-step3-03-序列化落库与回放.svg)

> 读图：比上张多了紫色的存储闭环（dumpd → 存储 → load → 回放）、黄色的存储契约、绿色的安全边界。三层各就各位。

**① 存：对象 → 纯数据 → 数据库**

```python
# store.py：第 3 版，序列化落库
import json
import sqlite3
import warnings

from langchain_core.load import dumpd
from langchain_core.messages import BaseMessage

warnings.filterwarnings("ignore", category=DeprecationWarning)

SCHEMA = """
CREATE TABLE IF NOT EXISTS messages (
    session_id  TEXT NOT NULL,
    seq         INTEGER NOT NULL,
    payload     TEXT NOT NULL,
    PRIMARY KEY (session_id, seq)
)
"""


def init_db(path: str = "chat.db") -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.execute(SCHEMA)
    return conn


def save_messages(conn, session_id: str, messages: list[BaseMessage]) -> None:
    """按轮次落库：一条消息一行，seq 保证顺序。"""
    for i, msg in enumerate(messages):
        conn.execute(
            "INSERT OR REPLACE INTO messages (session_id, seq, payload) VALUES (?, ?, ?)",
            (session_id, i, json.dumps(dumpd(msg), ensure_ascii=False)),
        )
    conn.commit()
```

**② 取：纯数据 → 对象 → 继续对话（回放）**

```python
# store.py（续）：还原与回放
from langchain_core.load import load


def load_messages(conn, session_id: str) -> list[BaseMessage]:
    """还原历史；含 tool_calls / ToolMessage 也原样回来。"""
    rows = conn.execute(
        "SELECT payload FROM messages WHERE session_id = ? ORDER BY seq",
        (session_id,),
    ).fetchall()
    data = [json.loads(row[0]) for row in rows]
    # allowed_objects='messages'：显式声明"只含聊天消息"，消除未来版本的默认值变更警告
    return load(data, allowed_objects="messages")


def replay(conn, session_id: str, model) -> None:
    """回放：把历史原样接回去，再问一句，验证记忆是否还在。"""
    history = load_messages(conn, session_id)
    print(f"--- 回放 {session_id}：共 {len(history)} 条 ---")
    for m in history:
        print(f"  [{m.type}] {str(m.content)[:40]}")
    result = model.invoke(history + [("human", "我叫什么名字？")])
    print("回放提问 →", result.content)
```

**③ 安全边界（红线，务必照做）**：`load()` 会实例化 Python 对象、可能触发副作用，**绝不要对不可信或未认证来源的数据调用它**。本课实测：`load` 处于 beta（运行时提示 `LangChainBetaWarning`），且未来版本要求显式传 `allowed_objects`——传 `allowed_objects="messages"` 即可消除该警告（实测有效）。

```python
# ✅ 正确：只 load 自己存进去的数据
history = load(data, allowed_objects="messages")

# ❌ 错误：load 来自用户上传 / 第三方接口的消息数据
# history = load(untrusted_data)
```

**④ 现在的日常节奏**：每轮结束 `save_messages` → 下次会话 `load_messages` 接回 → 需要复现时用 `replay` 单独回放某会话。历史从「看天吃饭的内存变量」变成「可按轮次检索、可裁剪、可回放的资产」。

## 🎯 会用标志

做到这三条，就算把本课「用起来了」：

1. 给你一段字符串拼接历史的代码，能改写成标准消息对象列表，并说清角色注入风险是怎么消失的；
2. 能把消息列表序列化落库、再还原继续对话，且工具调用（`tool_calls` / `tool_call_id` 配对）不丢；
3. 能说清 `load()` 的安全红线，并写出带 `allowed_objects` 的正确调用。

---

⬅️ **上一课**：[实战 2：给模型接入加一道「主备保险」](02-Models模型层.md)
➡️ **下一课**：实战 4（Tools 工具）待编写
