"""事实抽取与冲突检测：把"记忆"这件事做对的业务核心。

知识点回指：
- 阶段 2 · 课 6「长期记忆落地（语义 / 情景）」——三类记忆分层
- 阶段 3 · 课 10「节点级超时 / 重试 / 错误处理」——抽取失败不能整轮崩

设计要点：
- 抽取走**规则**而不是 LLM：合规要可解释、可复现（同项目 1 的判定原则）
- 每条事实带 kind（语义 / 情景 / 程序）与 risk（是否需人工确认）
- **冲突检测**是本项目相对项目 1 的新增难点：新事实和已存档的打架，不能直接覆盖
"""
import re
from typing import Any

# ---- 抽取规则（可解释、可复现）----
# 每条规则：正则 → (kind, 字段, 需确认?)
#   kind: profile=语义 / episode=情景 / rule=程序
#   需确认: 涉及联系方式、金额、法律承诺的，一律拦下人工看一眼

EXTRACT_RULES: list[tuple[str, str, str, bool]] = [
    # (正则, kind, 语义字段/标签, 是否高风险)
    (r"偏好(.{1,6}?)(?:沟通|联系)", "profile", "prefers", True),
    (r"(?:我的|叫我)(\S{1,8})", "profile", "nickname", False),
    (r"喜欢(.{1,10})", "profile", "likes", False),
    (r"投诉(.{1,20})", "episode", "complaint", True),
    (r"买了(.{1,15})", "episode", "purchase", False),
    (r"(?:以后|以后都|别)(?:再)?(.{0,10}?)(?:我|给我)?(?:发短信|打电话|联系)", "rule", "contact", True),
    (r"不要(.{1,15})", "rule", "avoid", True),
]

# ---- 冲突判定：同字段不同值即冲突 ----
CONFLICT_FIELDS = {"prefers", "nickname", "contact"}


def extract_facts(message: str) -> list[dict[str, Any]]:
    """从一条用户消息里抽出候选事实。

    返回结构：
        [{"kind": "profile|episode|rule", "field": str, "value": str,
          "risk": bool, "source": 原文片段}]
    """
    facts: list[dict[str, Any]] = []
    for pattern, kind, field, risk in EXTRACT_RULES:
        for m in re.finditer(pattern, message):
            value = (m.group(1) or "").strip()
            if not value:
                continue
            facts.append(
                {
                    "kind": kind,
                    "field": field,
                    "value": value,
                    "risk": risk,
                    "source": m.group(0),
                }
            )
    return facts


def detect_conflicts(
    candidates: list[dict[str, Any]],
    profile: dict[str, Any],
    rules: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """检测候选事实与已存档内容的冲突。

    只检查语义字段与规矩——经历是追加的，不存在冲突。
    """
    conflicts: list[dict[str, Any]] = []
    for c in candidates:
        field = c["field"]
        if field not in CONFLICT_FIELDS:
            continue

        if c["kind"] == "profile" and field in profile:
            old = profile[field]
            if old != c["value"]:
                conflicts.append(
                    {
                        "field": field,
                        "old": old,
                        "new": c["value"],
                        "reason": "档案里已有不同的值",
                    }
                )

        if c["kind"] == "rule":
            for r in rules:
                if r.get("field") == field and r.get("value") != c["value"]:
                    conflicts.append(
                        {
                            "field": field,
                            "old": r.get("value"),
                            "new": c["value"],
                            "reason": "已有规矩与新说法冲突",
                        }
                    )
    return conflicts


def needs_confirm(candidates: list[dict[str, Any]]) -> bool:
    """是否有一条候选事实需要人工确认。"""
    return any(c["risk"] for c in candidates)
