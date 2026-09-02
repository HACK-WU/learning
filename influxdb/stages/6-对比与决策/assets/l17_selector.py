#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
L17 · 实验 A：五款候选选型决策打分器（✅ 本机实跑）
=====================================================

把「哪个更好」翻译成「在我的约束下，哪个能用、哪个更省事」。

设计原则（三条，缺一不可）：

  1. 先排雷再打分 —— 某些场景下某候选是「硬不可行」，不是「分数低」。
     这类用 BLOCKER 单独列出，不参与排序。忽略这一步，就会出现
     「选型会上排名第一的方案，上线三周后被一个硬限制打回」。
  2. 每条规则标注依据 —— ⭐ 官方一手文档 / ⚠️ 假设或推算 / 📌 本课推导。
  3. 权重由场景决定 —— 六个维度在不同场景下权重不同，不存在通用最优解。

⚠️ 本脚本的分数是「决策辅助」不是「基准测试」：它回答的是
   「以我现在的约束，哪条路最省事」，不回答「谁的性能更强」。

纯标准库，Python 3.11 实跑。
"""

from dataclasses import dataclass, field
from typing import Callable, Dict, List, Tuple

# ============================================================
# 常量区（每条都标依据，改代码前先改依据）
# ============================================================

# ⭐ InfluxDB 3 Core：query-file-limit 默认 432，gen1-duration 默认 10min
#    432 × 10min = 72h = 3 天，超限制直接报错（L11 官方 config-options 原文核实）
INFLUX_CORE_QUERY_FILE_LIMIT = 432
INFLUX_CORE_GEN1_MINUTES = 10
INFLUX_CORE_MAX_QUERY_DAYS = (
    INFLUX_CORE_QUERY_FILE_LIMIT * INFLUX_CORE_GEN1_MINUTES
) / (24 * 60)  # = 3.0

# ⭐ Prometheus：--storage.tsdb.retention.time 默认 15d（官方 storage 页原文）
PROM_DEFAULT_RETENTION_DAYS = 15

# ⭐ Prometheus：平均每个样本 1-2 字节（官方 storage 页原文）
PROM_BYTES_PER_SAMPLE = (1, 2)

# ⭐ InfluxDB：L13 已核实的容量锚点「10 万点/秒 × 30 天 ≈ 1 TB（典型压缩比）」
#    反推压缩后每点字节数 —— ⚠️ 这是从官方锚点反推，非官方直接给出的数字
INFLUX_ANCHOR_POINTS_PER_SEC = 100_000
INFLUX_ANCHOR_DAYS = 30
INFLUX_ANCHOR_TB = 1.0
INFLUX_BYTES_PER_POINT = (
    INFLUX_ANCHOR_TB * 1024**4
    / (INFLUX_ANCHOR_POINTS_PER_SEC * 86400 * INFLUX_ANCHOR_DAYS)
)

# ⭐ ClickHouse：MergeTree 默认 index_granularity = 8192 行/粒度（官方 MergeTree 页）
# ⭐ ClickHouse：parts_to_throw_insert 默认 3000（超过报 Too Many Parts）
CK_INDEX_GRANULARITY = 8192
CK_PARTS_TO_THROW_INSERT = 3000

# ⭐ TimescaleDB：hypercore 列存压缩 >90%，官方口径「up to 98%」
#    （官方 hypercore 页原文）；连续聚合压缩率官方博客实测 61%
TS_COMPRESSION_PCT = 90
TS_CAGG_COMPRESSION_PCT = 61

# ⚠️ VictoriaMetrics 官网首页自述（厂商自述基准，非中立第三方）
#    「outperforms InfluxDB and TimescaleDB by up to 20x」
#    「10x less RAM than InfluxDB」
#    「up to 70x more data points ... than TimescaleDB」
#    「7x less storage space than Prometheus/Thanos/Cortex」
VM_CLAIM = {
    "speed_vs_influx": 20,
    "ram_vs_influx": 10,
    "points_vs_timescale": 70,
    "storage_vs_prom": 7,
}

CANDIDATES = ["InfluxDB 3 Core", "TimescaleDB", "VictoriaMetrics", "ClickHouse", "Prometheus"]

DIMENSIONS = ["写入", "查询", "压缩", "生态", "运维", "长期保留"]


# ============================================================
# 场景定义
# ============================================================

@dataclass
class Scenario:
    """一个选型场景。字段直接对应选型会上会被问到的那些问题。"""
    name: str
    retention_days: int        # 需要「能查到」的天数（不是「能存多久」）
    points_per_sec: int        # 每秒数据点数
    series_count: int          # 时间线/序列数量
    needs_join: bool           # 是否需要 JOIN 业务维表
    has_prometheus: bool       # 是否已有 Prometheus
    has_postgres: bool         # 是否已有 PostgreSQL（含 DBA）
    k8s_native: bool           # 是否 K8s 环境
    short_lived_jobs: bool     # 是否有短生命周期任务（batch / cronjob / FaaS）
    query_pattern: str         # dashboard / ad-hoc / alerting / mixed
    weights: Dict[str, float] = field(default_factory=dict)


SCENARIOS: List[Scenario] = [
    Scenario(
        name="场景 1 · IoT 设备遥测",
        retention_days=90,
        points_per_sec=50_000,
        series_count=500_000,
        needs_join=False,
        has_prometheus=False,
        has_postgres=False,
        k8s_native=False,
        short_lived_jobs=False,
        query_pattern="dashboard",
        weights={"写入": 1.5, "查询": 1.0, "压缩": 1.5, "生态": 1.0, "运维": 1.0, "长期保留": 2.0},
    ),
    Scenario(
        name="场景 2 · APM / K8s 微服务监控",
        retention_days=15,
        points_per_sec=800_000,
        series_count=5_000_000,
        needs_join=False,
        has_prometheus=True,
        has_postgres=False,
        k8s_native=True,
        short_lived_jobs=True,
        query_pattern="alerting",
        weights={"写入": 1.5, "查询": 1.5, "压缩": 1.0, "生态": 2.0, "运维": 1.0, "长期保留": 1.0},
    ),
    Scenario(
        name="场景 3 · 业务指标分析（要 JOIN 维表）",
        retention_days=730,
        points_per_sec=20_000,
        series_count=50_000,
        needs_join=True,
        has_prometheus=False,
        has_postgres=True,
        k8s_native=False,
        short_lived_jobs=False,
        query_pattern="ad-hoc",
        weights={"写入": 0.5, "查询": 2.0, "压缩": 1.0, "生态": 1.0, "运维": 1.0, "长期保留": 1.5},
    ),
    Scenario(
        name="场景 4 · 混合负载（实时监控 + 历史分析）",
        retention_days=180,
        points_per_sec=300_000,
        series_count=2_000_000,
        needs_join=True,
        has_prometheus=True,
        has_postgres=False,
        k8s_native=True,
        short_lived_jobs=False,
        query_pattern="mixed",
        weights={"写入": 1.5, "查询": 1.5, "压缩": 1.0, "生态": 1.5, "运维": 1.0, "长期保留": 1.5},
    ),
]


# ============================================================
# 排雷规则（BLOCKER）：硬不可行，不参与打分
# ============================================================

def blockers(cand: str, s: Scenario) -> List[str]:
    """返回该候选在该场景下的硬伤列表。非空即视为不可行。"""
    out: List[str] = []

    if cand == "InfluxDB 3 Core":
        # ⭐ 432 文件 × 10min = 3 天。超过就是报错，不是变慢（L11 官方核实）
        if s.retention_days > INFLUX_CORE_MAX_QUERY_DAYS:
            out.append(
                f"要查 {s.retention_days} 天，但 Core 可查窗口只有 "
                f"{INFLUX_CORE_MAX_QUERY_DAYS:.0f} 天"
                f"（432 文件 × 10min，超限直接报错）→ 需 Enterprise 或第三方直读 Parquet"
            )
        # ⭐ L6 官方硬限制：库 5 / 表 2000 / 列 500
        if s.series_count > 10_000_000:
            out.append("序列量级远超 Core 定位（Core 官方定位 edge / non-critical，L13）")

    if cand == "Prometheus":
        # ⭐ 官方 storage 页：本地存储非集群非复制，默认保留 15 天
        if s.retention_days > PROM_DEFAULT_RETENTION_DAYS:
            out.append(
                f"要查 {s.retention_days} 天，本地存储默认 {PROM_DEFAULT_RETENTION_DAYS} 天；"
                f"官方明说本地存储不集群不复制 → 长期保留必须接远程存储"
            )
        # ⭐ 官方 FAQ 与 storage 页：Prometheus 是「指标」系统，不是通用分析库
        if s.needs_join:
            out.append("PromQL 不支持 JOIN 业务维表（官方定位：收集处理指标，不是分析库）")

    if cand == "VictoriaMetrics":
        if s.needs_join:
            out.append("MetricsQL 不支持 JOIN 业务维表（PromQL 超集，同属指标模型）")

    if cand == "ClickHouse":
        # ⭐ 官方：小批量写入会产生大量 part，parts_to_throw_insert 默认 3000 即报错
        if s.points_per_sec < 1000:
            out.append(
                f"写入速率过低（{s.points_per_sec}/s），小批量会产生大量 part，"
                f"官方默认 3000 part 即报 Too Many Parts → 需外部攒批"
            )

    if cand == "TimescaleDB":
        if s.points_per_sec > 1_000_000:
            out.append(
                f"写入速率 {s.points_per_sec:,}/s 超出 PostgreSQL 单实例舒适区"
                f"（⚠️ 该阈值为工程经验值，非官方硬限制）"
            )

    return out


# ============================================================
# 六维打分规则：每条返回 (0~5 分, 理由)
# ============================================================

def score_influx(dim: str, s: Scenario) -> Tuple[int, str]:
    if dim == "写入":
        # ⭐ Telegraf 生态 + 对象存储无盘架构；⚠️ 但库/表/列有硬限制
        sc = 5 if s.points_per_sec >= 100_000 else 4
        return sc, "Telegraf 生态成熟 + Parquet 列存写入路径；⚠️ 库 5 / 表 2000 / 列 500 硬限制"
    if dim == "查询":
        if s.needs_join:
            return 1, "3.x 只有 SQL/InfluxQL，JOIN 维表能力弱（📌 非官方定位）"
        return 4, "SQL 为主（DataFusion），时间分桶/窗口函数完备，监控类查询顺手"
    if dim == "压缩":
        return 4, f"Parquet 列存压缩；⚠️ 由官方锚点反推约 {INFLUX_BYTES_PER_POINT:.1f} 字节/点"
    if dim == "生态":
        return 5, "Telegraf（300+ 插件 · 保守口径）+ Grafana 原生支持，采集侧最强（L16 已学）"
    if dim == "运维":
        return 4, "单二进制 + 对象存储，部署简单；⚠️ Core 无内建 backup 命令（L13）"
    if dim == "长期保留":
        # ⭐ 无 compactor，文件数只增不减
        return 1, "Core 无 compactor，90 天约 12,960 文件；存得下但查不到（L10/L11）"
    return 0, ""


def score_timescale(dim: str, s: Scenario) -> Tuple[int, str]:
    if dim == "写入":
        sc = 3 if s.points_per_sec <= 200_000 else 2
        return sc, "写入走 PostgreSQL 事务路径，吞吐不如专用 TSDB；⚠️ 经验判断"
    if dim == "查询":
        if s.needs_join:
            return 5, "标准 PostgreSQL SQL：JOIN / 窗口函数 / CTE 全支持，唯一全能选手"
        return 4, "time_bucket + 连续聚合（增量刷新，普通物化视图做不到）"
    if dim == "压缩":
        return 4, f"hypercore 列存压缩 >{TS_COMPRESSION_PCT}%（⭐ 官方）；⚠️ 连续聚合仅 {TS_CAGG_COMPRESSION_PCT}%（官方博客实测）"
    if dim == "生态":
        sc = 5 if s.has_postgres else 3
        return sc, "整个 PostgreSQL 生态复用（备份/权限/监控/DBA 技能）"
    if dim == "运维":
        sc = 5 if s.has_postgres else 2
        return sc, "已有 PG 则近乎零新增组件；否则要引入并维护一整套 PostgreSQL"
    if dim == "长期保留":
        return 5, "保留策略 + 分层存储到 S3（⭐ 官方 bottomless tiering），无文件数天花板"
    return 0, ""


def score_victoria(dim: str, s: Scenario) -> Tuple[int, str]:
    if dim == "写入":
        sc = 5 if s.has_prometheus else 4
        return sc, "兼容 Prometheus remote_write，且支持 InfluxDB line protocol（⭐ 官方）"
    if dim == "查询":
        if s.needs_join:
            return 1, "MetricsQL 无 JOIN（PromQL 超集，仍是指标模型）"
        sc = 4 if s.has_prometheus else 2
        return sc, "MetricsQL 向后兼容 PromQL；⚠️ 官方承认存在有意差异（rate/NaN/rollup）"
    if dim == "压缩":
        # ⚠️ 关键：厂商自述「7x 优于 Prometheus」只是方向性结论，
        #    按本课口径纪律，自述基准不能当决策依据 → 不给满分。
        #    这与脚本其余部分「⭐ 官方参数 / ⚠️ 自述推算」的标注纪律保持一致。
        return 4, "⚠️ 厂商自述 7x 优于 Prometheus —— 方向可信，但自述基准不作决策依据（故不给 5 分）"
    if dim == "生态":
        sc = 5 if s.has_prometheus else 2
        return sc, "可作 Prometheus 的长期存储层，Grafana 直接用 Prometheus datasource"
    if dim == "运维":
        return 4, "单节点 all-in-one 单二进制；集群版三组件（vminsert/vmselect/vmstorage）"
    if dim == "长期保留":
        return 5, "设计目标即长期存储（⭐ 官方：long-term remote storage for Prometheus）"
    return 0, ""


def score_clickhouse(dim: str, s: Scenario) -> Tuple[int, str]:
    if dim == "写入":
        sc = 5 if s.points_per_sec >= 100_000 else 2
        return sc, f"批量写入极强；⚠️ 小批量会撞 Too Many Parts（官方默认 {CK_PARTS_TO_THROW_INSERT} part）"
    if dim == "查询":
        if s.query_pattern in ("ad-hoc", "mixed"):
            return 5, "分析型最强：JOIN / 物化视图 / projection / 近似分位数全支持"
        return 3, "分析能力强，但监控类查询（率值/分位）需手写，不如 PromQL 顺手"
    if dim == "压缩":
        return 5, "列存压缩强，官方日志示例 194 MB → 24 MB（约 8x）"
    if dim == "生态":
        return 3, "数据与 BI 生态强；⚠️ 监控采集侧需自建（无 Telegraf 级生态）"
    if dim == "运维":
        return 2, "分布式部署复杂；⭐ ORDER BY 建后不可改，改键要重建表重导数据"
    if dim == "长期保留":
        return 5, "TTL 原生支持 DELETE / TO DISK / TO VOLUME / GROUP BY（⭐ 官方）"
    return 0, ""


def score_prometheus(dim: str, s: Scenario) -> Tuple[int, str]:
    if dim == "写入":
        if s.short_lived_jobs:
            return 2, "拉取模型对短生命周期任务不友好，需 Pushgateway（⭐ 官方：仅推荐批处理场景）"
        return 4, "拉取模型，服务端控速；⚠️ 但目标必须可被服务端访问到"
    if dim == "查询":
        if s.needs_join:
            return 1, "PromQL 不支持 JOIN（⭐ 官方 FAQ：Prometheus 是指标系统不是事件日志系统）"
        sc = 5 if s.query_pattern == "alerting" else 3
        return sc, "PromQL 监控语义最强（rate/histogram_quantile）；⚠️ 分析类查询弱"
    if dim == "压缩":
        return 4, f"官方原文 1-2 字节/样本（⭐），样本级压缩优秀"
    if dim == "生态":
        sc = 5 if s.k8s_native else 3
        return sc, "K8s 事实标准 + Alertmanager 原生 + 服务发现内置（⭐ 官方设计）"
    if dim == "运维":
        return 5, "单二进制、无外部依赖，运维最简单；⚠️ 但非集群非复制（⭐ 官方明说）"
    if dim == "长期保留":
        return 1, "本地存储默认 15 天且不集群不复制（⭐ 官方）；长期保留必须外挂"
    return 0, ""


SCORERS: Dict[str, Callable[[str, Scenario], Tuple[int, str]]] = {
    "InfluxDB 3 Core": score_influx,
    "TimescaleDB": score_timescale,
    "VictoriaMetrics": score_victoria,
    "ClickHouse": score_clickhouse,
    "Prometheus": score_prometheus,
}


# ============================================================
# 主流程
# ============================================================

def evaluate(s: Scenario) -> Tuple[List[Tuple[str, float, List[str]]], Dict[str, List[str]]]:
    """返回 (可用候选的加权分排序, 全部候选的 blocker 表)"""
    all_blockers: Dict[str, List[str]] = {}
    ranked: List[Tuple[str, float]] = []

    for cand in CANDIDATES:
        bl = blockers(cand, s)
        all_blockers[cand] = bl
        if bl:
            continue  # 有硬伤，不参与排名

        total, wsum = 0.0, 0.0
        for dim, w in s.weights.items():
            sc, _ = SCORERS[cand](dim, s)
            total += sc * w
            wsum += w
        ranked.append((cand, total / wsum if wsum else 0.0))

    ranked.sort(key=lambda x: -x[1])
    return ranked, all_blockers


def main() -> None:
    print("=" * 78)
    print("L17 实验 A · 五款候选选型决策打分器")
    print("=" * 78)

    # ---- 前置：先展示常量与依据 ----
    print("\n【规则常量与依据】")
    print(f"  InfluxDB Core 可查窗口 : {INFLUX_CORE_MAX_QUERY_DAYS:.0f} 天"
          f"  ⭐ 432 文件 × 10min（官方 config-options）")
    print(f"  Prometheus 默认保留    : {PROM_DEFAULT_RETENTION_DAYS} 天"
          f"  ⭐ --storage.tsdb.retention.time 默认值")
    print(f"  Prometheus 每样本字节  : {PROM_BYTES_PER_SAMPLE[0]}-{PROM_BYTES_PER_SAMPLE[1]} B"
          f"  ⭐ 官方 storage 页原文")
    print(f"  InfluxDB 压缩后每点    : {INFLUX_BYTES_PER_POINT:.2f} B"
          f"  ⚠️ 由官方锚点「10万点/秒×30天≈1TB」反推")
    print(f"  ClickHouse part 上限   : {CK_PARTS_TO_THROW_INSERT}"
          f"  ⭐ parts_to_throw_insert 默认值")
    print(f"  TimescaleDB 压缩率     : >{TS_COMPRESSION_PCT}%"
          f"  ⭐ 官方 hypercore 页")

    for s in SCENARIOS:
        print("\n" + "=" * 78)
        print(f"▶ {s.name}")
        print("=" * 78)
        print(f"  保留(可查) {s.retention_days} 天 · {s.points_per_sec:,} 点/秒 · "
              f"{s.series_count:,} 序列 · 查询模式 {s.query_pattern}")
        print(f"  要 JOIN 维表 {'是' if s.needs_join else '否'} · "
              f"已有 Prometheus {'是' if s.has_prometheus else '否'} · "
              f"已有 PostgreSQL {'是' if s.has_postgres else '否'} · "
              f"K8s {'是' if s.k8s_native else '否'} · "
              f"短生命周期任务 {'有' if s.short_lived_jobs else '无'}")

        ranked, all_blockers = evaluate(s)

        # ---- 排雷区 ----
        blocked = {c: b for c, b in all_blockers.items() if b}
        if blocked:
            print(f"\n  🚫 排雷（{len(blocked)} 款硬不可行，不参与排名）：")
            for cand, bl in blocked.items():
                for i, reason in enumerate(bl):
                    prefix = "     ├─" if i < len(bl) - 1 else "     └─"
                    print(f"{prefix} {cand}：{reason}")
        else:
            print("\n  ✅ 无硬伤候选，全部参与排名")

        # ---- 打分明细 ----
        print(f"\n  📊 打分明细（0-5 分，权重已按本场景调整）：")
        header = "     " + "候选".ljust(18) + "".join(d.ljust(8) for d in DIMENSIONS) + "加权"
        print(header)
        print("     " + "-" * (len(header) - 5))
        for cand in CANDIDATES:
            if all_blockers[cand]:
                cells = "".join("—".ljust(8) for _ in DIMENSIONS)
                print(f"     " + cand.ljust(18) + cells + "  (排雷)")
                continue
            cells, total, wsum = "", 0.0, 0.0
            for dim in DIMENSIONS:
                sc, _ = SCORERS[cand](dim, s)
                w = s.weights[dim]
                total += sc * w
                wsum += w
                cells += f"{sc}".ljust(8)
            print(f"     " + cand.ljust(18) + cells + f"{total / wsum:.2f}")

        # ---- 结论 ----
        print(f"\n  🏆 可用候选排序：")
        for i, (cand, sc) in enumerate(ranked, 1):
            print(f"     {i}. {cand.ljust(18)} {sc:.2f} 分")
        if not ranked:
            print("     （无可用候选 —— 说明该场景需要组合方案，见讲义第五幕）")

        # ---- 关键理由 ----
        print(f"\n  💬 排名前二的关键理由：")
        for cand, _ in ranked[:2]:
            best_dim, best_sc, best_reason = None, -1, ""
            for dim in DIMENSIONS:
                sc, reason = SCORERS[cand](dim, s)
                if sc > best_sc:
                    best_dim, best_sc, best_reason = dim, sc, reason
            worst_dim, worst_sc, worst_reason = None, 99, ""
            for dim in DIMENSIONS:
                sc, reason = SCORERS[cand](dim, s)
                if sc < worst_sc:
                    worst_dim, worst_sc, worst_reason = dim, sc, reason
            print(f"     【{cand}】")
            print(f"        最强项 {best_dim}（{best_sc}/5）：{best_reason}")
            print(f"        最弱项 {worst_dim}（{worst_sc}/5）：{worst_reason}")

    # ---- 收束 ----
    print("\n" + "=" * 78)
    print("📌 从四个场景能读出什么")
    print("=" * 78)
    print("  1. 没有一款在四个场景里都排第一 —— 所谓「最好的时序数据库」是个伪命题。")
    print("  2. 排雷比打分重要：场景 1 里 InfluxDB Core 不是「分数低」，是「查不到」。")
    print("  3. 已有基础设施（Prometheus / PostgreSQL）权重极高 —— 选型是算总账，")
    print("     不是算单项分。")
    print("  4. 混合负载（场景 4）逼出组合方案：这也正是 L19 要解决的事。")
    print("  5. 【口径纪律自检】VictoriaMetrics 压缩维度初版给了 5 分，但依据只是厂商自述；")
    print("     本课明确要求「自述基准不作决策依据」→ 已降为 4 分。")
    print("     这类「嘴上说慎引、手上打满分」的错，正是选型文档最常犯的。")


if __name__ == "__main__":
    main()
