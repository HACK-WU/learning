"""可注入的"外部来源"：让测试能确定性地模拟成功 / 抖动 / 永久失败。

知识点回指：
- 阶段 4 · 课 12「单元与集成测试」——依赖注入 + 测试替身
- 阶段 3 · 课 10「节点级超时 / 重试 / 错误处理」——可重试 vs 不可重试的区分

设计要点：
- 真实项目里这里是 HTTP 调用。教学项目里抽成接口，测试才能确定性地跑。
- 异常分两类，这个分类决定了重试策略怎么配：
    - TransientError（网络抖动）→ 可重试
    - PermanentError（参数错 / 404）→ 不该重试，重试也白搭
"""
import random
from typing import Any, Protocol


class TransientError(Exception):
    """可重试的错误：网络抖动、限流、临时不可用。"""


class PermanentError(Exception):
    """不可重试的错误：参数错、资源不存在、权限不足。"""


class Source(Protocol):
    """外部来源接口。"""

    name: str

    def fetch(self, query: str) -> str:
        """取数据；失败抛 TransientError 或 PermanentError。"""
        ...


class FlakySource:
    """会抖动的来源：前 N 次失败，之后成功。

    用来演示 RetryPolicy 真的在重试。
    """

    def __init__(self, name: str, *, fail_times: int = 2, data: str = "数据"):
        self.name = name
        self.fail_times = fail_times
        self.data = data
        self.calls = 0

    def fetch(self, query: str) -> str:
        self.calls += 1
        if self.calls <= self.fail_times:
            raise TransientError(f"{self.name} 第 {self.calls} 次抖动")
        return f"{self.data}（来自 {self.name}）"


class DeadSource:
    """永久失败的来源：重试多少次都没用。

    用来演示"不该重试的别重试"——配错 retry_on 会白白浪费 N 次调用。
    """

    def __init__(self, name: str, reason: str = "404 不存在"):
        self.name = name
        self.reason = reason

    def fetch(self, query: str) -> str:
        raise PermanentError(f"{self.name}: {self.reason}")


class GoodSource:
    """一次就成功的来源。"""

    def __init__(self, name: str, data: str | None = None):
        self.name = name
        self._data = data or f"{name}的数据"

    def fetch(self, query: str) -> str:
        return self._data


class RandomSource:
    """随机失败的来源：按概率抛 TransientError。

    演示真实场景下的不确定性——结论要用聚合而不是单点。
    """

    def __init__(self, name: str, *, fail_rate: float = 0.5, seed: int = 42):
        self.name = name
        self.fail_rate = fail_rate
        self._rng = random.Random(seed)

    def fetch(self, query: str) -> str:
        if self._rng.random() < self.fail_rate:
            raise TransientError(f"{self.name} 随机抖动")
        return f"{self.name}的数据"


class SourceRegistry:
    """来源注册表：名字 → 来源对象。节点通过它解耦具体实现。"""

    def __init__(self, sources: list[Source] | None = None):
        self._map: dict[str, Source] = {}
        for s in sources or []:
            self._map[s.name] = s

    def register(self, source: Source) -> None:
        self._map[source.name] = source

    def get(self, name: str) -> Source:
        if name not in self._map:
            raise PermanentError(f"未知来源: {name}")
        return self._map[name]

    def names(self) -> list[str]:
        return list(self._map.keys())
