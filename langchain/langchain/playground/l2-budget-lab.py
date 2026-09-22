"""带 token 预算控制的请求拼装。实测于 Python 3.12.13 / tiktoken 0.14.0。"""
import tiktoken
from dataclasses import dataclass

# 编码对象创建开销大，模块级创建一次，全局复用
ENC = tiktoken.get_encoding("cl100k_base")

# 给响应和消息边界开销留的余量（经验值，别设成 0）
RESPONSE_BUFFER = 512
MESSAGE_OVERHEAD = 4  # 每条消息的角色标记等额外开销


@dataclass
class Budget:
    """token 预算：窗口上限 - 要留给响应的部分。"""

    max_context: int
    response_buffer: int = RESPONSE_BUFFER

    @property
    def available(self) -> int:
        return self.max_context - self.response_buffer


def count_tokens(text: str) -> int:
    return len(ENC.encode(text))


def count_messages(messages: list[dict]) -> int:
    """算一组消息的总 token，含每条消息的结构开销。"""
    total = 0
    for msg in messages:
        total += count_tokens(msg["content"]) + MESSAGE_OVERHEAD
    return total


def build_messages(system_prompt: str, history: list[tuple[str, str]],
                   new_question: str, budget: Budget) -> list[dict]:
    """
    在预算内拼装消息。历史从最新往回加，加不下就停——宁可丢最老的，
    也不让请求超窗口失败。
    """
    messages = [{"role": "system", "content": system_prompt}]
    fixed = count_messages(messages) + count_tokens(new_question) + MESSAGE_OVERHEAD

    remaining = budget.available - fixed
    if remaining <= 0:
        raise ValueError(
            f"系统提示词 + 新问题已占 {fixed} token，"
            f"超出可用预算 {budget.available}，请缩短系统提示词"
        )

    # 从最新的历史往回加，加不下就停
    kept: list[dict] = []
    used = 0
    for q, a in reversed(history):
        pair = [{"role": "user", "content": q}, {"role": "assistant", "content": a}]
        cost = count_messages(pair)
        if used + cost > remaining:
            break
        kept = pair + kept
        used += cost

    messages.extend(kept)
    messages.append({"role": "user", "content": new_question})
    return messages


# ---- 用一下 ----
SYSTEM_PROMPT = "你是一个专业的客服助手，请用友好、耐心、专业的语气回答用户的问题。"
conversation = [
    ("我上周买的订单还没发货，能帮我查一下吗？", "好的，请提供您的订单号。"),
    ("订单号是 20260915001。", "已查询到，您的订单处于待发货状态。"),
    ("那大概什么时候能发？", "通常 48 小时内发出，请耐心等待。"),
]

budget = Budget(max_context=8192)
messages = build_messages(SYSTEM_PROMPT, conversation, "能加急吗？", budget)

total = count_messages(messages)
print(f"消息数：{len(messages)}")
print(f"本次输入 token：{total}")
print(f"可用预算：{budget.available}")
print(f"预算占用：{total / budget.available:.1%}")
