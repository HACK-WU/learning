"""research_agent 包。

会重试和降级的调研流水线：Send 扇出 + 子图状态隔离 + 重试策略 + 优雅降级。
知识点主线：容错与子图（阶段 3 · 课 10）。
"""
from .graph import build_graph, run
from .sources import (
    DeadSource,
    FlakySource,
    GoodSource,
    PermanentError,
    RandomSource,
    SourceRegistry,
    TransientError,
)
from .subgraph import build_source_subgraph

__all__ = [
    "build_graph",
    "run",
    "build_source_subgraph",
    "SourceRegistry",
    "GoodSource",
    "FlakySource",
    "DeadSource",
    "RandomSource",
    "TransientError",
    "PermanentError",
]
