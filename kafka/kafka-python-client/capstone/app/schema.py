"""课 13 —— 订单事件 Schema（课 9 序列化与 Schema Registry 落地）。

设计取舍：
  生产里该用 Avro/Protobuf + Schema Registry（本课工程接入点见 README）。
  但为了让 `docker compose up` 零外部依赖就能跑，这里用 **JSON + 手写校验**：
  - 格式自描述，debugging 直观（课 9 讲过 JSON 无 schema 的治理代价）
  - 校验逻辑即"契约"，坏消息在入口就被拦下，不会污染下游 topic

对应课程：课 9（序列化）、课 12（分层测试里的契约测试）。
"""

from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from typing import Any

# ---------- 契约定义 ----------

VALID_CURRENCIES = {"CNY", "USD", "EUR"}
MAX_AMOUNT = 10_000_000  # 单笔金额上限，防脏数据

ORDER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "required": ["order_id", "user_id", "amount", "currency"],
    "properties": {
        "order_id": {"type": "string", "minLength": 1, "maxLength": 64},
        "user_id": {"type": "string", "minLength": 1, "maxLength": 64},
        "amount": {"type": "number", "exclusiveMinimum": 0, "maximum": MAX_AMOUNT},
        "currency": {"type": "string", "enum": sorted(VALID_CURRENCIES)},
        "items": {"type": "array", "maxItems": 100},
    },
}


class ValidationError(ValueError):
    """消息不符合契约。

    与「处理失败」严格区分：
      - ValidationError  => 消息本身是坏的，**重试一万次也不会成功** => 进 DLQ
      - 业务异常         => 可能是下游抖动，**重试有意义** => 重试
    这个区分是本课核心设计之一（课 6 确认语义 + 课 12 错误处理）。
    """

    def __init__(self, order_id: str, reason: str):
        super().__init__(f"order_id={order_id}: {reason}")
        self.order_id = order_id
        self.reason = reason


@dataclass
class OrderEvent:
    order_id: str
    user_id: str
    amount: float
    currency: str
    items: list[dict] | None = None

    def to_json(self) -> bytes:
        return json.dumps(asdict(self), ensure_ascii=False).encode("utf-8")

    @classmethod
    def from_json(cls, raw: bytes) -> "OrderEvent":
        try:
            d = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            raise ValidationError("<unknown>", f"非合法 JSON: {e}") from e
        if not isinstance(d, dict):
            raise ValidationError("<unknown>", f"期望对象，实得 {type(d).__name__}")
        validate_order(d)
        return cls(
            order_id=d["order_id"],
            user_id=d["user_id"],
            amount=float(d["amount"]),
            currency=d["currency"],
            items=d.get("items"),
        )


def validate_order(d: dict) -> None:
    """手写校验器。

    为什么不用 jsonschema 库：l11 装了 jsonschema 4.26，但**手写能让错误信息
    更可控**，且不需要在热路径上加载 schema。生产环境建议还是用库 + Registry。

    抛 ValidationError（不是返回 False）——让调用方无法"忘记检查返回值"。
    """
    missing = [k for k in ORDER_SCHEMA["required"] if k not in d]
    if missing:
        raise ValidationError(str(d.get("order_id", "<unknown>")), f"缺字段 {missing}")

    oid = d["order_id"]
    if not isinstance(oid, str) or not oid or len(oid) > 64:
        raise ValidationError(str(oid), "order_id 须为 1-64 字符字符串")

    amt = d["amount"]
    # bool 是 int 的子类，这里显式排除（Python 经典陷阱）
    if isinstance(amt, bool) or not isinstance(amt, (int, float)):
        raise ValidationError(oid, f"amount 须为数字，实得 {type(amt).__name__}")
    if amt <= 0:
        raise ValidationError(oid, f"amount 须 > 0，实得 {amt}")
    if amt > MAX_AMOUNT:
        raise ValidationError(oid, f"amount 超过上限 {MAX_AMOUNT}")

    cur = d["currency"]
    if cur not in VALID_CURRENCIES:
        raise ValidationError(oid, f"currency 非法：{cur!r}，须为 {sorted(VALID_CURRENCIES)}")

    items = d.get("items")
    if items is not None:
        if not isinstance(items, list):
            raise ValidationError(oid, f"items 须为数组，实得 {type(items).__name__}")
        if len(items) > 100:
            raise ValidationError(oid, f"items 超过 100 条上限：{len(items)}")
