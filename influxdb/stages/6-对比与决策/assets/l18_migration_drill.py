#!/usr/bin/env python3.11
# -*- coding: utf-8 -*-
"""
L18 实验 B：迁移演练与回滚规划器

做什么：
    把一次「1.x/2.x -> 3.x」的迁移拆成 7 个阶段，对每一阶段回答三个问题：

        Q1 这一步做完，我们还能回到昨天吗？（可逆 / 有条件可逆 / 不可逆）
        Q2 这一步的验证方法是什么？（能用什么命令证明它做对了）
        Q3 这一步失败时，爆炸半径有多大？（只影响新系统 / 影响写入 / 影响老系统）

    再叠加一个专项：3.10+ 的 catalog v2 -> v3 单向迁移。
    官方原话是 "Upgrading to InfluxDB 3.10 is a one-way migration"，
    但备份路径**取决于你从哪个版本升上来** —— 选错路径 = 备份了一个空壳。

不做什么：
    不连数据库、不发请求、不读配置。纯静态推演 + 官方一手事实。

运行：
    C:\\Users\\v_wypgwu\\.local\\bin\\python3.11.exe l18_migration_drill.py

出处图例：
    官方   官方文档原文（docs.influxdata.com、官方 release notes、官方博客）
    已核实 本课程前序课已核实并写入 00-学习档案.md 的条目
"""

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# 一、官方一手常量
# ---------------------------------------------------------------------------

# 官方：catalog v2 -> v3 单向迁移的备份路径（3.10.0 release notes 原文）
# "The paths depend on the version you're upgrading from:"
#   "3.4.0 or later: {prefix}/catalog/v2/logs/ and {prefix}/catalog/v2/snapshot"
#   "Before 3.4.0:   {prefix}/catalogs/ and {prefix}/_catalog_checkpoint"
# "Restoring these objects is the only way to roll back to 3.9.x."
CATALOG_BACKUP_GE_340 = ["{prefix}/catalog/v2/logs/", "{prefix}/catalog/v2/snapshot"]
CATALOG_BACKUP_LT_340 = ["{prefix}/catalogs/", "{prefix}/_catalog_checkpoint"]

# 官方原话（3.10.0 release notes）：
# "On a cluster running 3.4.0 or later, {prefix}/catalogs/ and {prefix}/_catalog_checkpoint
#  may still be present as leftovers from an earlier catalog format.
#  They aren't current and aren't a valid rollback source."
CATALOG_LEFTOVER_TRAP = [
    "{prefix}/catalogs/",
    "{prefix}/_catalog_checkpoint",
]

# Core 硬限制（L6 已核实）
CORE_MAX_DATABASES = 5
CORE_MAX_TABLES = 2000
CORE_MAX_COLUMNS = 500

# L11/L13 已核实：可查窗口 = 432 文件 x gen1 10 分钟 = 3 天
QUERY_FILE_LIMIT = 432
GEN1_MINUTES = 10
MAX_QUERY_DAYS = QUERY_FILE_LIMIT * GEN1_MINUTES / (24 * 60)   # 3.0

# L12 已核实：批量写入双阈值
BATCH_LINES = 10_000
BATCH_BYTES = 10 * 1024 * 1024

# ---------------------------------------------------------------------------
# 二、阶段定义
# ---------------------------------------------------------------------------

REV_OK = "REV"      # 可逆：随时能退回
REV_COND = "CND"    # 有条件可逆：只在某个时间窗内可退
REV_NO = "NO"       # 不可逆：做完就没有回头路

REV_LABEL = {
    REV_OK: "可逆",
    REV_COND: "有条件可逆",
    REV_NO: "不可逆",
}

# 爆炸半径
BLAST_NEW = "仅新系统"
BLAST_WRITE = "影响写入"
BLASS_OLD = "影响老系统"

BLAST_SCORE = {BLAST_NEW: 1, BLAST_WRITE: 2, BLASS_OLD: 3}


@dataclass
class Stage:
    sid: str
    name: str
    reversible: str
    window: str                 # 可逆窗口（若是有条件可逆）
    verify: str                 # 验证方法（可照抄的命令或判断标准）
    blast: str                  # 爆炸半径
    rollback: str               # 怎么退
    trap: str = ""              # 这一步最常见的坑


def build_stages() -> List[Stage]:
    return [
        Stage(
            "S1", "盘点：schema 与容量自查",
            REV_OK,
            "随时",
            "统计每个 measurement 的列数、tag/field 同名情况、库与 rp 的组合数",
            BLAST_NEW,
            "无需回退，只是读老库",
            trap="最容易漏的是「tag 与 field 同名」——1.x 会静默改名，"
                 "你按 1.x 的清单导出，到 3.x 才发现写入失败，此时文件已经导完了",
        ),
        Stage(
            "S2", "建库：在 3.x 上建好目标 database",
            REV_OK,
            "随时（库是空的，删掉重来即可）",
            "influxdb3 show databases；核对保留期参数（永久保留 = 不传 --retention-period）",
            BLAST_NEW,
            "influxdb3 delete database",
            trap=f"永久保留千万别写 0d —— 那是立刻全删；Core 库上限 {CORE_MAX_DATABASES} 个，"
                 "1.x 一个 db 拆多个 rp 的写法摊平后很容易撞上",
        ),
        Stage(
            "S3", "双写：老系统照写，新系统并行写一份",
            REV_OK,
            "随时（停掉新写入即可）",
            "两边查同一时间窗的 COUNT(*)，差值应在可接受范围",
            BLAST_WRITE,
            "停掉指向 3.x 的 writer，老系统不受影响",
            trap="官方兼容性端点只保证「写入」，不保证「写入语义完全一致」——"
                 "tag 集合与列顺序由首次写入决定，双写的第一条数据就把 schema 定死了。"
                 "另：双写期间 tag 集合一旦定死就不可改，若后面发现漏了 tag，只能删库重来",
        ),
        Stage(
            "S4", "回填：导出历史数据写入 3.x",
            REV_OK,
            "随时（3.x 侧的库可以删掉重导）",
            "按时间窗分段比对 COUNT(*) 与若干抽样点的值",
            BLAST_NEW,
            "删库重导；老系统数据未动",
            trap="导出必须带 -lponly（只出行协议，不带 InfluxQL DDL/DML）；"
                 "回填时按时间分批，不要一个巨大文件",
        ),
        Stage(
            "S5", "校验：逐项对账",
            REV_OK,
            "随时",
            "库级 COUNT、表级 COUNT、抽样点比对、tag 基数比对",
            BLAST_NEW,
            "不通过就回到 S4 重导，或回到 S3 补写",
            trap="只比对 COUNT 是不够的 —— 列顺序、tag/field 类型、"
                 "精度解释方式都可能不同但 COUNT 相同",
        ),
        Stage(
            "S6", "切读：把查询流量切到 3.x",
            REV_COND,
            "只要老系统还没下线，随时可以切回去",
            "灰度：先切 1 个面板跑 24 小时，再全量",
            BLASS_OLD,
            "把查询客户端指回老系统",
            trap=f"Core 只能查最近 {MAX_QUERY_DAYS:.0f} 天 —— 一旦切读，"
                 "任何超过这个窗口的查询都会报错，而老系统上它是正常的",
        ),
        Stage(
            "S7", "下线：停掉老系统的写入与存储",
            REV_NO,
            "无（除非你在 S6 之前留了完整备份）",
            "确认无客户端指向老系统后停机",
            BLASS_OLD,
            "只能靠备份恢复，没有「撤销」按钮",
            trap="这是唯一真正不可逆的一步。前面六步都可以重来，"
                 "这一步做完，你的回滚方案从「切回去」降级为「从备份恢复」",
        ),
    ]


# ---------------------------------------------------------------------------
# 三、catalog 升级备份决策
# ---------------------------------------------------------------------------

@dataclass
class CatalogCase:
    ver_from: str
    ver_to: str
    ge_340: bool
    correct_paths: List[str]
    trap_paths: List[str]
    note: str


def build_catalog_cases() -> List[CatalogCase]:
    return [
        CatalogCase(
            "3.2.0", "3.10.0", False,
            CATALOG_BACKUP_LT_340, [],
            "低于 3.4.0，备份老路径",
        ),
        CatalogCase(
            "3.4.0", "3.10.0", True,
            CATALOG_BACKUP_GE_340, CATALOG_LEFTOVER_TRAP,
            "恰好是分界线，用新路径",
        ),
        CatalogCase(
            "3.9.5", "3.10.0", True,
            CATALOG_BACKUP_GE_340, CATALOG_LEFTOVER_TRAP,
            "新路径；注意旧目录可能还在，但是残留",
        ),
        CatalogCase(
            "3.9.7", "3.10.0", True,
            CATALOG_BACKUP_GE_340, CATALOG_LEFTOVER_TRAP,
            "新路径",
        ),
        CatalogCase(
            "3.10.0", "3.11.0", True,
            CATALOG_BACKUP_GE_340, CATALOG_LEFTOVER_TRAP,
            "已是 v3 catalog；但官方 3.11 仍提示 Catalog migration — back up your catalog before upgrading",
        ),
    ]


def pick_catalog_backup(ver_from: str) -> Tuple[List[str], List[str], str]:
    """按来源版本给出备份路径与陷阱路径。"""
    parts = ver_from.split(".")
    try:
        major, minor = int(parts[0]), int(parts[1])
    except (ValueError, IndexError):
        return ([], [], "无法解析版本号，请先 influxdb3 --version")
    # 3.10.0 及以后：catalog 已经是 v3，备份的对象变成 v3 目录本身
    if (major, minor) >= (3, 10):
        return (["{prefix}/catalog/"], [],
                "3.10.0+ 的 catalog 已是 v3（启动 3.10 时自动迁移过），"
                "备份整个 {prefix}/catalog/ 即可；⚠️ 备份它也不能让你退回 3.9.x")
    # 3.4.0 及以后用新路径
    if (major, minor) >= (3, 4):
        return (CATALOG_BACKUP_GE_340, CATALOG_LEFTOVER_TRAP, "3.4.0+ 用 catalog/v2 路径")
    return (CATALOG_BACKUP_LT_340, [], "低于 3.4.0 用 catalogs/ 路径")


# ---------------------------------------------------------------------------
# 四、回填批次规划（把导出文件切成可写入的批次）
# ---------------------------------------------------------------------------

def plan_batches(total_points: int, avg_line_bytes: int,
                 max_mb: int = 8) -> List[Dict[str, int]]:
    """
    按 L12 已核实的双阈值（10,000 行 或 10 MB，先到为准）规划回填批次。
    这里额外留了余量：默认单批压到 8 MB，给 gzip 与 HTTP 头留空间。

    注意 L12 已核实的一个撞车点：
        --max-http-request-size 默认 10mb，与 10 MB 批量阈值恰好相等，
        官方未说明批量阈值是压缩前还是压缩后 —— 故取保守策略。
    """
    cap_bytes = int(max_mb * 1024 * 1024)
    by_lines = BATCH_LINES
    by_bytes = max(1, cap_bytes // max(1, avg_line_bytes))
    per_batch = min(by_lines, by_bytes)
    if per_batch <= 0:
        return []
    batches: List[Dict[str, int]] = []
    left = total_points
    idx = 1
    while left > 0:
        take = min(per_batch, left)
        batches.append({
            "no": idx,
            "points": take,
            "bytes": take * avg_line_bytes,
        })
        left -= take
        idx += 1
        if idx > 10_000:      # 安全阀，防止参数异常导致死循环
            break
    return batches


# ---------------------------------------------------------------------------
# 五、打印
# ---------------------------------------------------------------------------

WIDTH = 78


def hr(ch: str = "=") -> None:
    print(ch * WIDTH)


def title(text: str) -> None:
    print()
    hr("=")
    print(text)
    hr("=")


def main() -> None:
    title("L18 实验 B：迁移演练与回滚规划器")
    print("模式：静态推演，不连数据库、不发请求。每条结论带出处。")

    # ---------------- 对照 1：七阶段可逆性矩阵 ----------------
    title("对照 1 ｜迁移七阶段的可逆性矩阵")
    print()
    stages = build_stages()
    print(f"{'ID':<5} {'阶段':<22} {'可逆性':<12} {'爆炸半径':<12} 可逆窗口")
    print("-" * WIDTH)
    for s in stages:
        print(f"{s.sid:<5} {s.name:<22} {REV_LABEL[s.reversible]:<12} {s.blast:<12} {s.window}")
    print()
    print("读法：「可逆窗口」这一列才是你真正该盯的。")
    print("      前五步都写着「随时」，意味着你在切读之前，随便怎么折腾都不伤老系统。")
    print("      S6 之后窗口开始关闭，S7 关死。")

    # ---------------- 对照 2：逐阶段详情 ----------------
    title("对照 2 ｜逐阶段的验证方法、回退动作与坑")
    print()
    for s in stages:
        print(f"--- {s.sid} {s.name}")
        print(f"    可逆性    ：{REV_LABEL[s.reversible]}（{s.window}）")
        print(f"    爆炸半径  ：{s.blast}")
        print(f"    怎么验证  ：{s.verify}")
        print(f"    怎么回退  ：{s.rollback}")
        print(f"    最常见的坑：{s.trap}")
        print()

    # ---------------- 对照 3：不可逆点定位 ----------------
    title("对照 3 ｜不可逆点定位（这是本课最该带走的结论）")
    print()
    irreversible = [s for s in stages if s.reversible == REV_NO]
    conditional = [s for s in stages if s.reversible == REV_COND]
    print(f"七阶段中：")
    print(f"  完全可逆      ：{len([s for s in stages if s.reversible == REV_OK])} 个")
    print(f"  有条件可逆    ：{len(conditional)} 个 -> {', '.join(s.sid for s in conditional)}")
    print(f"  不可逆        ：{len(irreversible)} 个 -> {', '.join(s.sid for s in irreversible)}")
    print()
    print("关键判断：")
    print("  S7（下线老系统）是唯一真正的不可逆点，但它是你自己选的、有时间准备的。")
    print("  真正的陷阱是 S6 —— 它看起来可逆（查询指回老系统即可），")
    print(f"  但一旦切读，超过 {MAX_QUERY_DAYS:.0f} 天窗口的查询在 Core 上直接报错，")
    print("  而同样的查询在老系统上是正常的。如果你的业务依赖历史查询，")
    print("  「切读」这一步实际上就已经把退路窄化了一半。")
    print()
    print("结论：把回滚演练放在 S6 之前做，不要放在 S7 之后。")
    print("      S7 之后再演练回滚，你练的已经不是回滚，是灾难恢复。")
    print()
    print("⚠️ 上面这张表只覆盖「1.x/2.x -> 3.x」的数据迁移。")
    print("   如果你是「3.9.x -> 3.10+」的版本升级，走的不是这七步，而是下面这条：")
    print("     ① influxdb3 --version 确认当前版本")
    print("     ② 按 3.4.0 分界线选对 catalog 备份路径（见对照 4）")
    print("     ③ 备份到别处并验证可读")
    print("     ④ 启动 3.10 —— 此刻触发 catalog v2->v3 单向迁移，之后无撤销按钮")
    print("   这条路径的可逆性不是「S7 才不可逆」，而是「第 ④ 步做完就不可逆」，")
    print("   比数据迁移的不可逆点靠前得多 —— 这也是本课把它单独列为知识点③的原因。")

    # ---------------- 对照 4：catalog 备份路径决策 ----------------
    title("对照 4 ｜3.10+ catalog 单向迁移：备份路径决策（官方 release notes）")
    print()
    print("官方原话：")
    print('  "Upgrading to InfluxDB 3.10 is a one-way migration."')
    print('  "Restoring these objects is the only way to roll back to 3.9.x."')
    print()
    print("所以备份路径的选择不是「最佳实践」，是「唯一退路」。")
    print()
    cases = build_catalog_cases()
    print(f"{'来源版本':<10} {'目标':<9} {'应备份的路径':<46} 陷阱目录")
    print("-" * WIDTH)
    for c in cases:
        paths = " / ".join(c.correct_paths) if c.correct_paths else "（已是 v3，仍建议备份）"
        trap = "有残留：" + " ".join(c.trap_paths) if c.trap_paths else "无"
        print(f"{c.ver_from:<10} {c.ver_to:<9} {paths:<46} {trap}")
    print()
    print("逐条判定（决策器自检）：")
    for c in cases:
        got, traps, why = pick_catalog_backup(c.ver_from)
        if not c.correct_paths:
            print(f"  {c.ver_from:<8} -> {why}")
            continue
        match = got == c.correct_paths
        print(f"  {c.ver_from:<8} -> {' '.join(got)}   与预期一致：{match}")
        if traps:
            print(f"             ⚠ 这些目录可能还在，但是残留、不是有效的回滚源：{' '.join(traps)}")
    print()
    print("官方对残留目录的原话：")
    print('  "On a cluster running 3.4.0 or later, {prefix}/catalogs/ and '
          '{prefix}/_catalog_checkpoint')
    print('   may still be present as leftovers from an earlier catalog format.')
    print('   They aren\'t current and aren\'t a valid rollback source."')
    print()
    print("这条特别阴险的地方在于：备份命令不会报错。")
    print("你备份了一个确实存在的目录，流程全绿，直到真正需要回滚的那天。")

    # ---------------- 对照 5：回填批次规划 ----------------
    title("对照 5 ｜回填批次规划（按 L12 已核实的双阈值）")
    print()
    print(f"官方批量写入双阈值：{BATCH_LINES:,} 行 或 {BATCH_BYTES // (1024*1024)} MB，先到为准")
    print(f"本规划器留余量：单批压到 8 MB（给 gzip 与 HTTP 头留空间）")
    print()
    scenarios = [
        ("小库 · 100 万点", 1_000_000, 80),
        ("中库 · 2000 万点", 20_000_000, 120),
        ("宽行 · 500 万点", 5_000_000, 600),
    ]
    for name, points, line_bytes in scenarios:
        batches = plan_batches(points, line_bytes)
        if not batches:
            print(f"{name}：参数异常，跳过")
            continue
        per = batches[0]["points"]
        per_bytes = batches[0]["bytes"]
        limit = "行数" if per == BATCH_LINES else "体积"
        total_mb = points * line_bytes / (1024 * 1024)
        print(f"{name}（平均行长 {line_bytes} 字节，总量约 {total_mb:,.0f} MB）")
        print(f"    单批 {per:,} 行 / {per_bytes / (1024*1024):.2f} MB —— 由【{limit}】阈值决定")
        print(f"    共 {len(batches):,} 批")
        last = batches[-1]
        print(f"    最后一批 {last['points']:,} 行（尾部不足一批，正常）")
        print()
    print("分界线验算（每行多大时从「行数先到」切换到「体积先到」）：")
    cross = BATCH_BYTES / BATCH_LINES
    print(f"    {BATCH_BYTES / (1024*1024)} MB / {BATCH_LINES:,} 行 = {cross:,.0f} 字节/行")
    print(f"    即：平均行长 < {cross:,.0f} 字节时行数先到，> {cross:,.0f} 字节时体积先到")
    print(f"    （L12 已核实：四档常见行长 60/120/300/1000 字节全部是行数先到）")
    print()
    print("回填提示：导出务必带 -lponly。不带它会导出 InfluxQL DDL/DML 语句，")
    print("          那些语句在 3.x 里大部分没用，混在行协议文件里只会让写入整批失败。")
    print()
    print("磁盘开销估算（导出成行协议后体积会变大，不是等大小拷贝）：")
    print(f"{'场景':<22} {'总点数':>14} {'行长':>7} {'导出体积':>12} {'建议预留':>12}")
    print("-" * WIDTH)
    for name, points, line_bytes in scenarios:
        total_mb = points * line_bytes / (1024 * 1024)
        need = total_mb * 1.2
        print(f"{name:<22} {points:>14,} {line_bytes:>7} {total_mb:>11,.0f}M {need:>11,.0f}M")
    print()
    print("行协议是文本格式，同一份数据导出后通常比 TSM 内部存储大 ——")
    print("          因为 TSM 有压缩，而行协议没有。1.x 官方页推荐加 -compress（gzip）。")
    print("          ⚠️ 别低估这一点：磁盘满了会导致导出中断，而中断在半途的导出文件最容易出问题。")

    # ---------------- 对照 6：收束 ----------------
    title("对照 6 ｜收束：迁移这件事真正难在哪")
    print()
    print("三条判断：")
    print("  1. 迁移的技术难点不在「把数据搬过去」，在「搬过去之后知道它是对的」。")
    print("     S5（校验）是七步里唯一没有产出物的一步，也是最容易为了赶进度被砍掉的一步。")
    print("  2. 可逆性不是二元的，是一个正在关闭的窗口。")
    print("     S1-S5 随时可退，S6 开始收窄，S7 关死。")
    print("     把风险动作尽量压在 S6 之前，是唯一能显著降低迁移风险的结构性手段。")
    print("  3. 3.10 的 catalog 升级是「自动 + 单向 + 静默成功」三件套。")
    print("     自动意味着你不需要做什么，单向意味着做错了退不回来，")
    print("     静默成功意味着你连「要不要确认一下」的机会都没有。")
    print("     唯一的应对就是：在启动 3.10 之前，先按版本选对路径备份。")
    print()
    print("关于「双写要写多久」—— 这个数不该拍脑袋，可以算：")
    print(f"  下限：覆盖你的对账周期（S5 要跑完，通常 1-3 天）")
    print(f"  上限：Core 的可查窗口 {MAX_QUERY_DAYS:.0f} 天 —— 双写超过这个时长，")
    print("        最早写进 3.x 的数据就已经查不到了，双写失去对照意义。")
    print("  所以 Core 上的双写窗口实际只有 1-3 天，很窄，S5 必须提前准备好脚本。")
    print("  （若是 Enterprise，没有 432 文件限制，窗口由你的存储成本决定。）")
    print()
    print("自检（本脚本不重复 L17 那类「嘴上说慎引、手上打满分」的错）：")
    all_stages = build_stages()
    has_irreversible = any(s.reversible == REV_NO for s in all_stages)
    last_is_irreversible = all_stages[-1].reversible == REV_NO
    print(f"  七阶段中包含不可逆步骤：{has_irreversible}")
    print(f"  不可逆步骤位于最后（S7）：{last_is_irreversible}")
    print(f"  pick_catalog_backup('3.9.5') 不返回残留目录："
          f"{CATALOG_LEFTOVER_TRAP[0] not in pick_catalog_backup('3.9.5')[0]}")
    print(f"  pick_catalog_backup('3.2.0') 返回老路径："
          f"{pick_catalog_backup('3.2.0')[0] == CATALOG_BACKUP_LT_340}")
    print()
    hr("=")


if __name__ == "__main__":
    main()
