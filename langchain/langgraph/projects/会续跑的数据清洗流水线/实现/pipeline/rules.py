"""可注入的清洗规则与"脏数据"来源。

知识点回指：
- 阶段 4 · 课 12「单元与集成测试」——确定性替身
- 阶段 3 · 课 11「两套 API 选型」——控制流就是 if / while

设计要点：
- 规则是纯函数（输入一行 → 输出修好的行 + 修了什么），好测、好组合。
- 「不确定」的情况不猜，标记出来等人工裁决——这是 interrupt 的用武之地。
"""
from dataclasses import dataclass
from typing import Any, Callable

from .models import Row


@dataclass
class Fix:
    """一次修复的记录。"""

    field: str
    before: Any
    after: Any
    rule: str


class Unclear(Exception):
    """数据含义不明，需要人工裁决（不是错误，是要确认）。"""


# ============================================================
# 规则：纯函数，输入 Row，返回 (修好的 dict, Fix 列表)
# ============================================================


def strip_whitespace(row: Row) -> tuple[dict, list[Fix]]:
    """去掉字符串首尾空格。"""
    out, fixes = {}, []
    for k, v in row.cleaned.items():
        if isinstance(v, str) and v != v.strip():
            out[k] = v.strip()
            fixes.append(Fix(k, repr(v), repr(v.strip()), "strip_whitespace"))
        else:
            out[k] = v
    return out, fixes


def normalize_empty(row: Row) -> tuple[dict, list[Fix]]:
    """空字符串 / "null" / "N/A" → None。"""
    out, fixes = {}, []
    nulls = {"", "null", "NULL", "N/A", "n/a", "-", "None"}
    for k, v in row.cleaned.items():
        if isinstance(v, str) and v.strip() in nulls:
            out[k] = None
            fixes.append(Fix(k, repr(v), "None", "normalize_empty"))
        else:
            out[k] = v
    return out, fixes


def coerce_types(row: Row, *, int_fields: tuple[str, ...] = ()) -> tuple[dict, list[Fix]]:
    """把能转成 int 的字符串转成 int。

    ⚠️ 转不了的**不猜**，抛 Unclear 交人工——这是刻意的设计：
    静默填默认值会在下游埋雷。
    """
    out, fixes = {}, []
    for k, v in row.cleaned.items():
        if k in int_fields and isinstance(v, str) and v.strip():
            try:
                out[k] = int(v)
                fixes.append(Fix(k, repr(v), out[k], "coerce_types"))
            except ValueError:
                raise Unclear(f"第 {row.id} 行字段 {k!r} 的值 {v!r} 不是合法整数")
        else:
            out[k] = v
    return out, fixes


def drop_unknown_fields(row: Row, *, allowed: tuple[str, ...]) -> tuple[dict, list[Fix]]:
    """丢掉不在白名单里的字段。"""
    out, fixes = {}, []
    for k, v in row.cleaned.items():
        if k in allowed:
            out[k] = v
        else:
            fixes.append(Fix(k, repr(v), "<删除>", "drop_unknown_fields"))
    return out, fixes


def require_fields(row: Row, *, required: tuple[str, ...]) -> tuple[dict, list[Fix]]:
    """必填字段缺失 → 记 error（不是异常，是这行不合格）。"""
    missing = [f for f in required if row.cleaned.get(f) in (None, "")]
    if missing:
        row.errors.append(f"缺少必填字段: {', '.join(missing)}")
    return row.cleaned, []


Rule = Callable[[Row], tuple[dict, list[Fix]]]


def default_rules(*, int_fields: tuple[str, ...] = (), allowed: tuple[str, ...] = (),
                  required: tuple[str, ...] = ()) -> list[tuple[str, Rule]]:
    """组装默认规则链（顺序有意义）。"""
    return [
        ("去空格", strip_whitespace),
        ("空值归一", normalize_empty),
        ("类型转换", lambda r: coerce_types(r, int_fields=int_fields)),
        ("丢未知字段", lambda r: drop_unknown_fields(r, allowed=allowed)),
        ("必填校验", lambda r: require_fields(r, required=required)),
    ]
