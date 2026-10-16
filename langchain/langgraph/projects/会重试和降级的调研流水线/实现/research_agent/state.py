"""调研流水线的状态定义。

知识点回指：
- 阶段 1 · 课 3「State 的定义与 reducer」——Annotated + add 累加语义
- 阶段 3 · 课 10「子图与状态隔离」——父子只传共有字段，私有字段各自留着

本项目演示两件事：
1. **Send 扇出**：一个查询拆成 N 个来源，并行去取
2. **子图状态隔离**：每个来源的调查是个子图，子图内部的中间产物
   （如"重试了几次"）不污染父图，只把结论交回去
"""
from typing import Annotated, Any

from operator import add
from typing_extensions import TypedDict


class SourceResult(TypedDict):
    """单个来源的调查结论（子图交给父图的成品）。"""

    source: str
    ok: bool
    data: str
    error: str
    attempts: int          # 这个来源重试了几次（子图内部才知道）


class ResearchState(TypedDict):
    """父图状态：一次调研任务的全局视图。

    只装"要汇总的东西"，不装每个来源的中间过程。
    """

    # ---- 输入 ----
    query: str
    sources: list[str]          # 要去哪些来源查

    # ---- 扇出产物 ----
    # 各来源的结论，累加
    results: Annotated[list[SourceResult], add]

    # ---- 汇总 ----
    # 成功的 / 失败的
    succeeded: list[str]
    failed: list[str]
    report: str

    # ---- 观测 ----
    trace: Annotated[list, add]


class SourceState(TypedDict):
    """子图状态：单个来源的调查过程。

    ⚠️ 关键：这里的 `scratch` 字段父图**没有声明**，
    所以子图内部的中间产物不会泄漏到父图（实测确认）。
    """

    source: str
    query: str

    # 子图私有：重试次数、原始报错——父图看不见
    scratch: Annotated[list, add]

    # 与父图共有的字段：结论会传回去
    result: SourceResult | None


def empty_state(query: str, sources: list[str]) -> ResearchState:
    """构造干净的初始状态。"""
    return {
        "query": query,
        "sources": sources,
        "results": [],
        "succeeded": [],
        "failed": [],
        "report": "",
        "trace": [],
    }
