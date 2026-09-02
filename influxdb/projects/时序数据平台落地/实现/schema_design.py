# -*- coding: utf-8 -*-
"""
schema_design.py —— 阶段 3 体检（L6 数据模型 / L7 Schema 设计与基数陷阱）

📌 回指：L6《数据模型：table、tag、field、timestamp》、L7《Schema 设计与基数陷阱》

本模块回答三个问题：
  1. 这套 schema 落进 Core 会不会撞硬限制（库 5 / 表 2000 / 列 500）
  2. 基数有多大、点密度是否低到让压缩失效
  3. 有没有把"需要按它查"误当成"它必须是 tag"
"""

from config import (
    CORE_MAX_COLUMNS, CORE_MAX_DATABASES, CORE_MAX_TABLES, Finding, Workload,
)

# 低基数字段做 tag 是安全的；高基数字段做 tag 会让基数爆炸
HIGH_CARDINALITY_THRESHOLD = 100_000
# 点密度低于此值，每个 series 攒不满一个压缩块，压缩率显著下降
MIN_HEALTHY_DENSITY = 0.01


def check_hard_limits(w: Workload) -> list:
    """⭐ L6 官方硬限制：Core 库 5 / 表 2000 / 列 500。"""
    out = []
    columns = len(w.tags) + len(w.fields) + 1          # +1 是 time

    checks = [
        ("数据库", w.databases, CORE_MAX_DATABASES),
        ("表", w.tables, CORE_MAX_TABLES),
        ("列", columns, CORE_MAX_COLUMNS),
    ]
    for label, actual, limit in checks:
        if actual > limit:
            out.append(Finding(
                "P0", "阶段 3 · L6",
                f"{label}数 {actual} 超过 Core 上限 {limit}",
                f"{label}数 {actual:,} > Core 上限 {limit:,}，建库/建表/写入会被直接拒绝。",
                "拆库拆表、把高基数字段降级为 field，或改用 Enterprise（官方口径更宽松，⚠️ 具体数字未公开）",
            ))
        elif actual > limit * 0.8:
            out.append(Finding(
                "P1", "阶段 3 · L6",
                f"{label}数 {actual} 接近 Core 上限 {limit}",
                f"已用掉 {actual / limit:.0%}，业务增长后会撞墙。",
                "现在就规划拆分路径，别等写入报错",
            ))
    return out


def check_cardinality(w: Workload) -> list:
    """📌 回指 L7：基数是乘法，点密度才是压缩的命门。"""
    out = []
    series = w.series
    density = w.point_density

    out.append(Finding(
        "INFO", "阶段 3 · L7",
        f"基数估算：{series:,} series，点密度 {density:.4f} 点/秒/series",
        "基数 = 各 tag 基数之积；点密度 = 每秒点数 ÷ series 数。",
        "以这两个数为基准判断下面的结论",
    ))

    if density < MIN_HEALTHY_DENSITY:
        worst = max(w.tags.items(), key=lambda kv: kv[1])
        out.append(Finding(
            "P0", "阶段 3 · L7",
            f"点密度 {density:.4f} 低于 {MIN_HEALTHY_DENSITY}，压缩基本失效",
            f"每个 series 平均 {1 / density:,.0f} 秒才有一个点，Parquet 压缩块攒不满，"
            f"存储量与查询开销会向「按 series 数」而非「按点数量级」退化。",
            f"把最高基数的 tag「{worst[0]}」（{worst[1]:,} 值）降级为 field，"
            "或把它折叠进 field 键名（L7 的宽 schema 折中方案）",
        ))

    for tag, card in w.tags.items():
        if card >= HIGH_CARDINALITY_THRESHOLD:
            out.append(Finding(
                "P1", "阶段 3 · L7",
                f"tag「{tag}」基数 {card:,} 已属高基数",
                f"它会让总基数乘以 {card:,}。",
                "确认是否真的需要按它分组/过滤 —— 见下一条「需要按某字段查 ≠ 它必须是 tag」",
            ))
    return out


def check_tag_field_choice(w: Workload) -> list:
    """⭐ L7 核心判据：需要按某字段查 ≠ 它必须是 tag。"""
    out = []
    if not w.need_join:
        return out

    high = [t for t, c in w.tags.items() if c >= HIGH_CARDINALITY_THRESHOLD]
    if high:
        out.append(Finding(
            "P0", "阶段 3 · L7",
            "把高基数字段当 tag，很可能是为了「能按它查」",
            f"涉及 tag：{', '.join(high)}。"
            "⚠️ Core 官方页面全文 0 次提及索引（L7 本机抓取核实），"
            "Clustered 更明文写着不索引 tag 值 —— tag 带来的不是索引加速，"
            "而是「参与分组与主键」的语义。靠加 tag 换查询速度在 InfluxDB 3 上不成立。",
            "若只是偶尔点查，改为 field + 时间范围过滤；若确实要按它聚合，接受基数代价并做降采样",
        ))
    return out


def check_naming(w: Workload) -> list:
    """⭐ L6：保留键有三类后果，_field/_measurement 是静默丢弃。"""
    out = []
    reserved_time = [t for t in list(w.tags) + list(w.fields) if t == "time"]
    reserved_silent = [t for t in list(w.tags) + list(w.fields)
                       if t in ("_field", "_measurement")]

    if reserved_time:
        out.append(Finding(
            "P0", "阶段 3 · L6",
            "字段名叫 time —— 写入会被拒绝",
            "time 是保留键，官方语义是拒绝写入（报错，有声音）。",
            "改名，如 ts / event_time",
        ))
    if reserved_silent:
        out.append(Finding(
            "P0", "阶段 3 · L6",
            f"字段名叫 {' / '.join(reserved_silent)} —— 数据会被静默丢弃",
            "这类保留键不报错，数据直接消失，是 L6 里最危险的一类：你以为写进去了。",
            "改名，并回查历史数据确认没有正在丢",
        ))
    return out


def run(w: Workload) -> list:
    return (check_hard_limits(w) + check_cardinality(w)
            + check_tag_field_choice(w) + check_naming(w))
