"""记忆助手的状态定义。

知识点回指：
- 阶段 1 · 课 3「State 的定义与 reducer」——Annotated + operator.add 累加语义
- 阶段 2 · 课 6「Store 与命名空间」——State 只装"这一轮的事"，长期记忆一律走 Store

关键设计（本项目与项目 1 最大的差异）：
- **State 里不存用户档案**。档案在 Store，按 user_id 分格。
- State 只承载：本轮输入、本轮抽取出的候选事实、需要人确认的东西、本轮日志。
- 这样设计的原因：State 是 thread 作用域（换会话就丢），Store 是 user 作用域（跨会话共享）。
"""
from typing import Annotated, Any

from operator import add
from typing_extensions import TypedDict


class MemoryState(TypedDict):
    """一次客服会话的状态（thread 作用域）。

    字段分四类：
    1. 输入：user_id / message
    2. 抽取产物：candidates（本轮从对话里抽出的候选事实）
    3. 控制字段：confirmed（人是否已确认）、skipped（是否跳过确认）
    4. 观测字段：trace（本轮每一步做了什么，便于回放与测试断言）
    """

    # ---- 输入 ----
    user_id: str
    message: str

    # ---- 抽取产物 ----
    # 候选事实：本轮从 message 里抽出来的，还没写档
    candidates: list[dict[str, Any]]
    # 冲突：新事实与已存档的事实打架，需要人裁决
    conflicts: list[dict[str, Any]]

    # ---- 控制字段 ----
    # need_confirm: 是否存在高风险事实需要人工确认
    need_confirm: bool
    # decision: 人工裁决结果（confirm / reject / skip）
    decision: str

    # ---- 观测字段 ----
    # 累加语义：每个节点 return {"trace": [...]} 会被追加而不是覆盖
    trace: Annotated[list, add]
    # 本轮最终回复
    reply: str


def empty_state(user_id: str, message: str) -> MemoryState:
    """构造干净的初始状态（测试与示例都用它，避免漏字段）。"""
    return {
        "user_id": user_id,
        "message": message,
        "candidates": [],
        "conflicts": [],
        "need_confirm": False,
        "decision": "",
        "trace": [],
        "reply": "",
    }
