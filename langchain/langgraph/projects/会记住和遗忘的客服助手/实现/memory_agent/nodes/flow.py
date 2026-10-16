"""客服助手的四个节点。

知识点回指：
- 阶段 2 · 课 6「Store 与命名空间」——节点签名 `*, store: BaseStore` 由框架注入
- 阶段 3 · 课 8「interrupt 的中断机制」——高风险写档前卡住等确认
- 阶段 3 · 课 10「节点级超时 / 重试 / 错误处理」——抽取失败兜底

⚠️ 本项目最关键的机制（已实测验证）：
    interrupt 之后的 resume **不会重放** interrupt 之前的节点。
    所以"抽取"节点里的 Store 写入是安全的，不会因人工确认而重复写。
    （探针 lg_store_probe6 实测：resume 后 counter 仍为 {n: 1}）
"""
import time
from typing import Any

from langgraph.store.base import BaseStore
from langgraph.types import interrupt

from ..extract import detect_conflicts, extract_facts, needs_confirm
from ..state import MemoryState
from ..store import MemStore


def recall(state: MemoryState, *, store: BaseStore) -> dict[str, Any]:
    """节点 1：回忆——从 Store 捞这个用户的三类记忆，装配上下文。

    为什么先回忆：后面的抽取要做冲突检测，得先知道"已经存了什么"。
    """
    mem = MemStore(store)
    uid = state["user_id"]

    profile = mem.get_profile(uid)
    rules = mem.enabled_rules(uid)
    episodes = mem.recent_episodes(uid, limit=5)

    return {
        "trace": [
            f"recall: profile={len(profile)}项 rules={len(rules)}条 episodes={len(episodes)}条"
        ],
        # 回忆结果不放 State（State 是 thread 作用域，下一轮就没了）
        # 但本轮后面要用，所以存进一个临时字段——见下方说明
        "_recalled": {"profile": profile, "rules": rules, "episodes": episodes},
    }


def extract(state: MemoryState, *, store: BaseStore) -> dict[str, Any]:
    """节点 2：抽取 + 冲突检测。

    走规则不 LLM：合规可解释、可复现。
    抽取失败（异常）不整轮崩——兜住返回空候选。
    """
    uid = state["user_id"]
    message = state["message"]

    try:
        candidates = extract_facts(message)
    except Exception as e:  # 抽取是尽力而为，不能因此中断服务
        return {
            "candidates": [],
            "conflicts": [],
            "need_confirm": False,
            "trace": [f"extract: 失败已兜住 ({type(e).__name__})"],
        }

    # 冲突检测需要已存档内容，这里重新读一次 Store（不依赖上游传值）
    mem = MemStore(store)
    profile = mem.get_profile(uid)
    rules = mem.all_rules(uid)
    conflicts = detect_conflicts(candidates, profile, rules)

    return {
        "candidates": candidates,
        "conflicts": conflicts,
        "need_confirm": needs_confirm(candidates),
        "trace": [
            f"extract: 候选{len(candidates)}条 冲突{len(conflicts)}条 需确认={needs_confirm(candidates)}"
        ],
    }


def confirm(state: MemoryState, *, store: BaseStore) -> dict[str, Any]:
    """节点 3：人工确认（仅高风险事实触发）。

    用 interrupt() 卡住，人裁决后 Command(resume=...) 续跑。
    裁决结果：confirm=照写 / reject=丢弃 / keep=保留旧值
    """
    payload = {
        "question": "以下记忆需要确认",
        "candidates": state["candidates"],
        "conflicts": state["conflicts"],
    }
    answer = interrupt(payload)

    decision = answer if isinstance(answer, str) else "confirm"
    return {
        "decision": decision,
        "trace": [f"confirm: 人工裁决={decision}"],
    }


def write_memory(state: MemoryState, *, store: BaseStore) -> dict[str, Any]:
    """节点 4：写档——按裁决结果把事实写进 Store 的三类格子。

    这是唯一写 Store 的地方（除 recall 的读），便于审计与回放。
    """
    mem = MemStore(store)
    uid = state["user_id"]
    decision = state.get("decision", "confirm")

    if decision == "reject":
        return {"trace": ["write: 已拒绝，不写档"], "reply": "好的，我没有记下这些。"}

    written: list[str] = []
    ts = int(time.time())

    for i, c in enumerate(state["candidates"]):
        if decision == "keep" and any(x["field"] == c["field"] for x in state["conflicts"]):
            continue  # 冲突字段保留旧值

        if c["kind"] == "profile":
            mem.patch_profile(uid, {c["field"]: c["value"]})
            written.append(f"档案.{c['field']}={c['value']}")

        elif c["kind"] == "rule":
            mem.add_rule(
                uid,
                f"r-{ts}-{i}",
                {"field": c["field"], "value": c["value"], "enabled": True, "source": c["source"]},
            )
            written.append(f"规矩.{c['field']}={c['value']}")

        elif c["kind"] == "episode":
            mem.add_episode(
                uid,
                f"ep-{ts}-{i}",
                {"field": c["field"], "value": c["value"], "ts": ts, "source": c["source"]},
            )
            written.append(f"经历.{c['field']}={c['value']}")

    reply = f"记下了：{', '.join(written)}" if written else "这次没有需要记住的新信息。"
    return {"trace": [f"write: 写入{len(written)}条"], "reply": reply}
