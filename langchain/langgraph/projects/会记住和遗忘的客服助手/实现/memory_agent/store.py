"""记忆后端抽象：MemStore 门面 + 命名空间约定 + 测试替身。

知识点回指：
- 阶段 2 · 课 6「Store 与命名空间」——namespace 分格、put / get / search
- 阶段 4 · 课 12「单元与集成测试」——依赖注入 + 测试替身

为什么要有这一层：
- 直接 `store.put(("u1", "profile"), ...)` 散落在各个节点里，命名空间字符串会到处重复、容易写错
- 抽成门面后，**命名空间约定只在一处**，节点只调语义化方法
- 换成 PostgresStore 时只改这里（生产落地路径）
"""
from typing import Any

from langgraph.store.base import BaseStore

# ---- 命名空间约定（SSOT）----
# 三类记忆各占一格：语义（档案）/ 情景（经历）/ 程序（规矩）

NS_PROFILE = "profile"      # 语义记忆：一份档案，固定 key
NS_EPISODE = "episodes"     # 情景记忆：一条一条的经历
NS_RULE = "rules"           # 程序记忆：生效的行为规矩

PROFILE_KEY = "profile"     # 语义记忆是单条，key 固定


def ns_profile(user_id: str) -> tuple[str, ...]:
    """语义记忆命名空间：(user_id, "profile")。

    ⚠️ 第一层必须是 user_id，不能是 thread_id。
    用 thread_id 当第一层 = 把柜子按会话分格，长期记忆退化成短期记忆（课 6 实测的坑）。
    """
    return (user_id, NS_PROFILE)


def ns_episode(user_id: str) -> tuple[str, ...]:
    """情景记忆命名空间：(user_id, "episodes")。"""
    return (user_id, NS_EPISODE)


def ns_rule(user_id: str) -> tuple[str, ...]:
    """程序记忆命名空间：(user_id, "rules")。"""
    return (user_id, NS_RULE)


class MemStore:
    """Store 门面：把命名空间约定与常用操作收在一处。

    节点只跟它打交道，不直接拼 namespace 元组。
    """

    def __init__(self, store: BaseStore, *, episode_limit: int = 20):
        self._store = store
        self.episode_limit = episode_limit

    # ---- 语义记忆：一份档案 ----
    def get_profile(self, user_id: str) -> dict[str, Any]:
        """读用户档案；没有则返回空 dict（不返回 None，省得调用方判空）。"""
        item = self._store.get(ns_profile(user_id), PROFILE_KEY)
        return dict(item.value) if item else {}

    def put_profile(self, user_id: str, profile: dict[str, Any]) -> None:
        """整体覆盖写档案（语义记忆是"一份"，不是累加）。"""
        self._store.put(ns_profile(user_id), PROFILE_KEY, profile)

    def patch_profile(self, user_id: str, patch: dict[str, Any]) -> dict[str, Any]:
        """局部更新档案：读出来 → 合并 → 写回。返回新档案。

        ⚠️ 这是"读改写"，并发下会丢更新。生产要用带 CAS 的后端；
        本项目单线程演示，代价写进设计决策.md。
        """
        cur = self.get_profile(user_id)
        cur.update(patch)
        self.put_profile(user_id, cur)
        return cur

    # ---- 情景记忆：一条条经历 ----
    def add_episode(self, user_id: str, key: str, episode: dict[str, Any]) -> None:
        """追加一条经历。key 由调用方保证唯一（如 ep-<时间戳>-<序号>）。"""
        self._store.put(ns_episode(user_id), key, episode)

    def recent_episodes(self, user_id: str, limit: int | None = None) -> list[dict[str, Any]]:
        """捞最近经历。

        ⚠️ 必须显式给 limit——search 默认只返回 10 条且不报错（课 6 实测的坑）。
        """
        n = limit if limit is not None else self.episode_limit
        items = self._store.search(ns_episode(user_id), limit=n)
        return [i.value for i in items]

    # ---- 程序记忆：生效的规矩 ----
    def add_rule(self, user_id: str, key: str, rule: dict[str, Any]) -> None:
        """写一条规矩。"""
        self._store.put(ns_rule(user_id), key, rule)

    def enabled_rules(self, user_id: str) -> list[dict[str, Any]]:
        """捞所有生效的规矩（filter 走 Store 侧过滤）。"""
        items = self._store.search(ns_rule(user_id), filter={"enabled": True})
        return [i.value for i in items]

    def all_rules(self, user_id: str) -> list[dict[str, Any]]:
        """捞全部规矩（含已禁用），用于冲突检测与审计。"""
        items = self._store.search(ns_rule(user_id), limit=100)
        return [i.value for i in items]


# ---- 测试替身 ----
class FakeStore:
    """不依赖 langgraph 的极简 Store 替身，用于纯单元测试。

    只实现本项目用到的四个方法：get / put / search / delete。
    语义与 InMemoryStore 对齐（含 search 默认 limit=10 的行为）。
    """

    def __init__(self):
        self._data: dict[tuple[str, ...], dict[str, dict[str, Any]]] = {}

    def get(self, namespace: tuple[str, ...], key: str):
        bucket = self._data.get(namespace, {})
        if key not in bucket:
            return None
        return _SimpleItem(namespace, key, bucket[key])

    def put(self, namespace: tuple[str, ...], key: str, value: dict[str, Any], **_: Any) -> None:
        self._data.setdefault(namespace, {})[key] = dict(value)

    def delete(self, namespace: tuple[str, ...], key: str) -> None:
        self._data.get(namespace, {}).pop(key, None)

    def search(
        self,
        namespace_prefix: tuple[str, ...],
        /,
        *,
        query: str | None = None,
        filter: dict[str, Any] | None = None,
        limit: int = 10,
        offset: int = 0,
    ):
        out = []
        for ns, bucket in self._data.items():
            if ns[: len(namespace_prefix)] != namespace_prefix:
                continue
            for key, value in bucket.items():
                if filter and not all(value.get(k) == v for k, v in filter.items()):
                    continue
                out.append(_SimpleItem(ns, key, value))
        return out[offset : offset + limit]


class _SimpleItem:
    """Item 的极简替身，只需有 namespace / key / value 三个属性。"""

    def __init__(self, namespace: tuple[str, ...], key: str, value: dict[str, Any]):
        self.namespace = namespace
        self.key = key
        self.value = value
