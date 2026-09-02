# -*- coding: utf-8 -*-
"""
config.py —— 全项目单一数据源（SSOT）

📌 设计决策 3 的产物：所有模块共享同一份 `Workload` 数据类与常量表，
   而不是每个模块各自解析一遍输入。代价是模块间存在耦合（见 设计决策.md 决策 3）。

本文件里的常量全部来自课程已核实的官方一手事实，改动前请先回到对应课时核对。
"""

from dataclasses import dataclass, field
from typing import Dict, List, Tuple

# ===== 阶段 4 · L11：可查窗口的硬约束 ============================
CORE_QUERY_FILE_LIMIT = 432          # ⭐ query-file-limit 默认值
CORE_GEN1_MINUTES = 10               # ⭐ gen1-duration 默认 10 分钟（最少档）
FILES_PER_DAY = 86_400 // (CORE_GEN1_MINUTES * 60)   # 144 个/天
CORE_MAX_QUERY_DAYS = CORE_QUERY_FILE_LIMIT * CORE_GEN1_MINUTES / (24 * 60)   # 3.0 天

# ⭐ L19 P0-1 修复：432 是 Core 的属性，不是 InfluxDB 的属性。
#    Enterprise / Serverless / Dedicated / Clustered 都有 compactor，会合并小文件。
SKU_FILE_LIMIT: Dict[str, int | None] = {
    "core": CORE_QUERY_FILE_LIMIT,   # 硬约束：超限直接报错
    "enterprise": None,              # 有 compactor，性能衰减而非报错
    "serverless": None,
    "dedicated": None,
    "clustered": None,
}

# ===== 阶段 3 · L6：Core 的硬限制 ================================
CORE_MAX_DATABASES = 5
CORE_MAX_TABLES = 2_000
CORE_MAX_COLUMNS = 500

# ===== 阶段 4 · L12：批量写入双阈值 ==============================
BATCH_LINES = 10_000                 # ⭐ 10,000 行
BATCH_BYTES = 10 * 1024 * 1024       # ⭐ 10 MB，whichever threshold is met first

# ===== 阶段 4 · L13：内存三默认（相加 90%）=======================
MEM_EXEC_POOL = 0.20                 # --exec-mem-pool-size
MEM_PARQUET_CACHE = 0.20             # --parquet-mem-cache-size
MEM_FORCE_SNAPSHOT = 0.50            # --force-snapshot-mem-size

# ===== 阶段 4 · L10：写入路径 ====================================
RAW_POINT_BYTES = 120                # ⚠️ 假设：典型 line protocol 行长 60-150 字节
COMPRESS_RATIO = 0.04                # ⚠️ 假设：典型 25x 压缩（官方口径 10-100x）

# ===== 阶段 5 · L14：保留期单位（⚠️ 非日历单位）=================
UNIT_DAYS: Dict[str, float] = {
    "h": 1 / 24, "d": 1.0, "w": 7.0,
    "mo": 30.0,     # ⭐ 官方：30 天，不是日历月（31 天）
    "y": 365.0,     # ⭐ 官方：365 天，不是日历年（365.25 天）
}
CALENDAR_MONTH_DAYS = 30.44          # 365.25 / 12，用于算 drift 幅度

# ===== 阶段 6 · L19：Serverless 官方单价 ========================
PRICE_WRITE_PER_MB = 0.0025
PRICE_QUERY_PER_100 = 0.012
PRICE_STORAGE_PER_GB_HOUR = 0.002
PRICE_EGRESS_PER_GB = 0.09
HOURS_PER_MONTH = 730
PRICE_STORAGE_PER_GB_MONTH = PRICE_STORAGE_PER_GB_HOUR * HOURS_PER_MONTH   # ≈ $1.46

# ===== 阶段 6 · L19：成本假设（⚠️ 需替换为本地真实值）==========
OPS_FTE_USD_MONTH = 15_000           # ⚠️ 假设：单人月成本（含社保等）
OPS_FTE_SELF = 0.5                   # 自托管运维投入
OPS_FTE_MANAGED = 0.1                # 托管后仍需的人
OBJ_STORAGE_PER_GB_MONTH = 0.023     # 对象存储单价
HOST_USD_MONTH = 240.0               # ⚠️ 假设：一台 16C64G 云主机
PRICE_QUERY_PER_100 = 0.012          # ⭐ Serverless 官方单价：$0.012 / 100 次查询
PRICE_HOST_SELF = HOST_USD_MONTH     # 自托管主机费（与 HOST_USD_MONTH 同源）

LEVEL_ORDER = {"P0": 0, "P1": 1, "P2": 2, "INFO": 3}


@dataclass
class Finding:
    """一次检查的结论。level 决定它是否会阻断交付。"""
    level: str          # P0 / P1 / P2 / INFO
    stage: str          # 形如 "阶段 4 · L11"
    title: str
    detail: str
    action: str


@dataclass
class Workload:
    """一份负载描述 = 一次选型与落地的全部输入。"""
    name: str
    pps: int                          # 每秒点数
    raw_retention_days: int           # 原始层要留多久
    query_window_days: int            # 业务要求能查多久
    tags: Dict[str, int]              # tag 名 → 取值基数
    fields: List[str] = field(default_factory=list)
    tables: int = 1
    databases: int = 1
    # 阶段 6 的约束
    source_version: str = "none"      # none / 1.x / 2.x
    need_join: bool = False
    need_native_v3_api: bool = False
    need_processing_engine: bool = False
    want_managed: bool = False
    need_ha: bool = False
    edge: bool = False
    ops_headcount: int = 2
    # 阶段 5 的采集与可视化
    telegraf: Dict[str, object] = field(default_factory=dict)
    dashboard_panels: int = 0
    dashboard_refresh_s: int = 0
    downsample_interval_min: int = 60
    # 保留期写法 —— 用于检测 L14/L18 的 reverse / drift 两类静默
    retention_period: str = "90d"    # 形如 "90d" / "3mo" / "0d" / "1y"
    compliance: bool = False         # 是否有合规要求（决定 drift 的严重度）

    @property
    def series(self) -> int:
        """📌 回指 L7：基数是各 tag 基数的乘积。"""
        n = 1
        for v in self.tags.values():
            n *= v
        return n

    @property
    def point_density(self) -> float:
        """📌 回指 L7：点密度 = 每秒点数 / series 数。趋近 0 则压缩失效。"""
        return self.pps / self.series if self.series else float("inf")


WORKLOADS: Dict[str, Workload] = {
    "iot": Workload(
        name="IoT 设备遥测",
        pps=50_000,
        raw_retention_days=90,
        query_window_days=90,
        tags={"device_id": 20_000, "site": 20, "sensor": 5},
        fields=["temperature", "humidity", "voltage"],
        tables=3,
        databases=2,
        want_managed=True,
        ops_headcount=1,
        downsample_interval_min=60,
        telegraf={"plugin": "outputs.influxdb_v2", "urls": ["http://a:8181", "http://b:8181"],
                  "database_tag": "site", "organization": "my-org"},
        dashboard_panels=12,
        dashboard_refresh_s=30,
        # ⚠️ 故意保留从 1.x 迁移过来的写法：0d 在老版本是"永久"，在 3.x 是"立刻全删"
        retention_period="0d",
        compliance=False,
    ),
    "k8s": Workload(
        name="K8s 微服务监控",
        pps=200_000,
        raw_retention_days=15,
        query_window_days=30,
        tags={"pod": 5_000, "namespace": 30, "container": 3, "node": 50},
        fields=["cpu", "memory", "net_in", "net_out"],
        tables=8,
        databases=1,
        need_native_v3_api=True,
        need_processing_engine=True,
        want_managed=True,
        need_ha=True,
        ops_headcount=2,
        downsample_interval_min=10,
        telegraf={"plugin": "outputs.influxdb_v3", "urls": ["http://a:8181"],
                  "organization": ""},
        dashboard_panels=30,
        dashboard_refresh_s=10,
        retention_period="3mo",       # ⚠️ = 90 天，比三个自然月（91.3 天）少 1.3 天
        compliance=False,
    ),
    "biz": Workload(
        name="业务指标分析（需 JOIN）",
        pps=8_000,
        raw_retention_days=365,
        query_window_days=365,
        tags={"order_id": 2_000_000, "region": 8},
        fields=["amount", "quantity"],
        tables=5,
        databases=1,
        need_join=True,
        source_version="1.x",
        ops_headcount=3,
        downsample_interval_min=1440,
        telegraf={"plugin": "outputs.influxdb_v3", "urls": ["http://a:8181"]},
        dashboard_panels=6,
        dashboard_refresh_s=300,
        # ⚠️ 合规要求留 1 个日历年（365.25 天），但 1y = 365 天 —— 且本场景有合规要求，判 P0
        retention_period="1y",
        compliance=True,
    ),
}
