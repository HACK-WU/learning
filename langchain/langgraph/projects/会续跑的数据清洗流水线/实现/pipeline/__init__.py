"""会续跑的数据清洗流水线。

用 Functional API（@entrypoint / @task）把一批脚本改造成
「能暂停、能续跑」的流水线——不用重写成图。
"""
from .flow import clean_row, detect_outliers, pipeline, run_batch
from .models import Batch, PipelineResult, Row, StageReport, make_batch
from .rules import (
    Unclear,
    coerce_types,
    default_rules,
    drop_unknown_fields,
    normalize_empty,
    require_fields,
    strip_whitespace,
)

__all__ = [
    "pipeline",
    "run_batch",
    "clean_row",
    "detect_outliers",
    "Batch",
    "Row",
    "StageReport",
    "PipelineResult",
    "make_batch",
    "default_rules",
    "strip_whitespace",
    "normalize_empty",
    "coerce_types",
    "drop_unknown_fields",
    "require_fields",
    "Unclear",
]
