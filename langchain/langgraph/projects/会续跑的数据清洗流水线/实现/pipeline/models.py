"""数据清洗流水线的数据模型。

知识点回指：
- 阶段 3 · 课 11「@entrypoint / @task 模型」
    —— Functional API 没有 State schema，用普通 dataclass / dict 传数据
- 阶段 3 · 课 11「previous 参数：Functional API 的状态」
    —— 跨调用累计靠 previous，不是具名字段

⚠️ 本项目刻意**不用 State schema**——这正是选 Functional API 的理由：
    清洗流程是"流水账"，中间过程不需要被逐格 inspect 和修改。
"""
from dataclasses import dataclass, field
from typing import Any


@dataclass
class Row:
    """一行待清洗的数据。"""

    id: int
    raw: dict[str, Any]
    cleaned: dict[str, Any] = field(default_factory=dict)
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


@dataclass
class Batch:
    """一批待清洗的数据。"""

    name: str
    rows: list[Row]
    source: str = "unknown"


@dataclass
class StageReport:
    """单个清洗阶段的报告。"""

    stage: str
    processed: int
    fixed: int
    failed: int
    details: list[str] = field(default_factory=list)


@dataclass
class PipelineResult:
    """流水线最终结果。"""

    batch: str
    total: int
    succeeded: int
    failed: int
    stages: list[StageReport]
    rows: list[Row]
    needs_review: list[int] = field(default_factory=list)

    def summary(self) -> str:
        lines = [
            f"批次「{self.batch}」清洗完成",
            f"  总计 {self.total} 行，成功 {self.succeeded}，失败 {self.failed}",
            "",
            "  各阶段：",
        ]
        for s in self.stages:
            lines.append(f"    · {s.stage}: 处理 {s.processed}，修 {s.fixed}，失败 {s.failed}")
        if self.needs_review:
            lines.append("")
            lines.append(f"  ⚠️ 待人工复核的行: {self.needs_review}")
        return "\n".join(lines)


def make_batch(name: str, raws: list[dict], source: str = "csv") -> Batch:
    """从原始 dict 列表构造批次。"""
    return Batch(
        name=name,
        source=source,
        rows=[Row(id=i, raw=dict(r)) for i, r in enumerate(raws)],
    )
