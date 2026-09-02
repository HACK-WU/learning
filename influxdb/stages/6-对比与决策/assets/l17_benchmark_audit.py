#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
L17 · 实验 B：基准数字「口径审计器」（✅ 本机实跑）
====================================================

overview 的口径纪律原文：
  「二手基准数字差异极大，汇报时只取方向性结论，
    不把具体数值写进决策文档。」

本课之前的课程反复踩过同一个坑（L16 的 P0：引用官方「10s 面板 ≈ $31/月」
时口径没对齐，一个算每面板 1 query、一个算 5 query，差 5 倍）。

所以本实验不复现别人的基准，而是做一件更实用的事：
  **拿到任何一个基准数字，先审它的口径，再决定能不能用。**

审计六问（缺一不可）：
  Q1 谁测的？        厂商 / 中立第三方 / 自己
  Q2 测的什么？      组件 vs 整体；写入 vs 查询 vs 压缩
  Q3 口径对齐了吗？  单位、分母、时间窗、行数/体积
  Q4 配置说清楚了吗？ 硬件、版本、并发、数据量级
  Q5 是峰值还是稳态？ best-of-N 还是可持续值
  Q6 能写进决策文档吗？ 前三问任一不过关 → 只能取方向

⚠️ Q0（v2 补，评审发现的分类缺陷）：
  上面六问默认「待审对象是一条性能宣称」。但真实清单里混着三类
  性质完全不同的东西，用同一套问法审会得出荒谬结论 —— 例如把
  「InfluxDB Core 只能查 3 天」这条**官方配置硬约束**判成
  「⚠️ 不能裸写数字」，而它恰恰是全课最硬的排雷依据。

  故增加 Q0「这条宣称属于哪一类」，三类分治：
    benchmark  —— 性能/容量宣称（六问全审）
    spec       —— 官方配置默认值、硬限制（只审「是否官方原文 + 是否版本敏感」）
    misread    —— 理解错误（不论是否 verified，一律 ❌；验证只能证伪）

纯标准库，Python 3.11 实跑（v2）。
"""

from dataclasses import dataclass
from typing import List, Optional

# ============================================================
# 数据结构
# ============================================================

@dataclass
class Claim:
    """一条待审宣称（claim）。字段对应审计六问 + Q0 分类。"""
    text: str                    # 宣称原文
    claim_kind: str              # Q0 分类：benchmark / spec / misread
    source_type: str             # vendor / third_party / in_house
    subject: str                 # 被测对象：component / full_stack
    workload: str                # write / query / compression / mixed
    unit_defined: bool           # Q3 单位与分母是否明确
    config_disclosed: bool       # Q4 配置是否披露
    peak_or_steady: str          # Q5 peak / steady / unknown
    already_verified: bool       # 是否已被我们自己的实测验证过
    note: str = ""


# ============================================================
# 审计规则
# ============================================================

def audit(c: Claim) -> List[tuple]:
    """返回 [(级别, 问题), ...]，级别取 INFO / WARN / BLOCK

    Q0 分类分治：
      misread   —— 理解错误，验证只能证伪不能证实 → 直接 BLOCK 收束
      spec      —— 官方配置默认值/硬限制，不审「厂商自述/峰值稳态」这类性能问法
      benchmark —— 性能/容量宣称，六问全审
    """
    issues: List[tuple] = []

    # ---- Q0 分类：理解错误，直接定案 ----
    if c.claim_kind == "misread":
        issues.append(
            ("BLOCK", "Q0 这是理解错误，不是数字误差："
                      "验证只能证伪，不能把一个错的认知变成对的")
        )
        return issues

    # ---- Q0 分类：官方规格/硬限制 ----
    # 这类不是「谁跑得快」的宣称，而是「它就是这样」的约束。
    # 拿审性能宣称的问法（Q1 厂商自述 / Q5 峰值稳态 / Q4 配置披露）去审它，
    # 会把最硬的排雷依据误判成「不可引用的软数字」。
    if c.claim_kind == "spec":
        issues.append(("INFO", "Q0 官方规格/硬限制：属于「约束」而非「性能宣称」，"
                               "不按基准数字的口径审"))
        if c.already_verified:
            issues.append(("INFO", "Q6 已由本课程官方一手核实（非道听途说）→ 可直接写入"))
        else:
            issues.append(("WARN", "Q6 未经核实：请先到官方文档核对原文与版本号"))
        if not c.unit_defined:
            issues.append(("WARN", "Q3 适用范围未写清：引用时请补全限定语"
                                   "（例：「默认 15 天」不是「最多 15 天」；「300+ 插件」要说明计了哪几类）"))
        issues.append(("INFO", "Q7 已随 Q6 带出版本号即可直接引用；⚠️ 默认值与硬限制会随版本变化"))
        return issues

    # ---- Q1 谁测的 ----
    if c.source_type == "vendor":
        issues.append(
            ("WARN", "Q1 厂商自述：方向可参考，数字不可直接引用"
                     "（厂商会选择对自己有利的对比对象与配置）")
        )
    elif c.source_type == "third_party":
        issues.append(("INFO", "Q1 中立第三方：可信度较高，但仍需核对测试时间（版本迭代会失效）"))
    else:
        issues.append(("INFO", "Q1 自己实测：可信度最高，但要写清楚环境与步骤"))

    # ---- Q2 测的什么：组件 vs 整体 ----
    if c.subject == "component":
        issues.append(
            ("WARN", "Q2 测的是单个组件：拿它跟「整体方案」比是不公平对照"
                     "（典型错误：拿 InfluxDB 存储 比 Prometheus 全套）")
        )

    # ---- Q3 口径 ----
    if not c.unit_defined:
        issues.append(
            ("BLOCK", "Q3 单位或分母未定义：这个数字无法复用，禁止写入决策文档"
                      "（L16 的 P0 就是这么来的：5 query 口径错配成 1 query，差 5 倍）")
        )

    # ---- Q4 配置披露 ----
    if not c.config_disclosed:
        issues.append(
            ("WARN", "Q4 配置未披露：无法判断该数字在你的环境下能否复现")
        )

    # ---- Q5 峰值还是稳态 ----
    if c.peak_or_steady == "unknown":
        issues.append(("WARN", "Q5 未说明是峰值还是稳态：容量规划只能用稳态值"))
    elif c.peak_or_steady == "peak":
        issues.append(
            ("BLOCK", "Q5 是峰值（best-of-N）：不能用于容量规划，"
                      "否则按它采购的机器在真实负载下会不够用")
        )

    # ---- Q6 是否已被自己验证 ----
    if c.already_verified:
        issues.append(("INFO", "Q6 已被我们自己的实测验证 → 可以写进决策文档"))
    else:
        issues.append(
            ("WARN", "Q6 未经自己验证：引用前务必先在自己的数据上复现一遍"
                     "（换数据集、换基数，结论可能完全翻转）")
        )

    return issues


def verdict(issues: List[tuple]) -> str:
    """根据问题级别给出处置结论。返回 (级别码, 展示文案)。"""
    levels = {lv for lv, _ in issues}
    if "BLOCK" in levels:
        return ("BLOCK", "❌ 禁止写入决策文档（只能内部讨论时提方向）")
    if "WARN" in levels:
        return ("WARN", "⚠️ 可写入，但必须标注来源与前提（不能裸写数字）")
    return ("OK", "✅ 可写入决策文档")


# ============================================================
# 待审计清单：全部是本课真实遇到过的宣称
# ============================================================

CLAIMS: List[Claim] = [
    Claim(
        text="VictoriaMetrics 比 InfluxDB 和 TimescaleDB 快 20 倍",
        claim_kind="benchmark",
        source_type="vendor",
        subject="component",
        workload="mixed",
        unit_defined=False,
        config_disclosed=False,
        peak_or_steady="unknown",
        already_verified=False,
        note="⭐ 出自 VictoriaMetrics 官网首页 Prominent features",
    ),
    Claim(
        text="VictoriaMetrics 内存用量是 InfluxDB 的 1/10",
        claim_kind="benchmark",
        source_type="vendor",
        subject="component",
        workload="mixed",
        unit_defined=True,
        config_disclosed=False,
        peak_or_steady="unknown",
        already_verified=False,
        note="⭐ 官网原文「10x less RAM than InfluxDB」，限定条件是「百万级时间线」",
    ),
    Claim(
        text="VictoriaMetrics 比 TimescaleDB 能多存 70 倍数据点",
        claim_kind="benchmark",
        source_type="vendor",
        subject="component",
        workload="compression",
        unit_defined=False,
        config_disclosed=False,
        peak_or_steady="unknown",
        already_verified=False,
        note="⭐ 官网「up to 70x」；注意 up to = 上界不是典型值",
    ),
    Claim(
        text="ClickHouse 某查询从 8.7 秒优化到 0.22 秒（约 40 倍）",
        claim_kind="benchmark",
        source_type="vendor",
        subject="component",
        workload="query",
        unit_defined=True,
        config_disclosed=True,
        peak_or_steady="steady",
        already_verified=False,
        note="⭐ ClickHouse 官方文档：配置了 ORDER BY + 全文索引 vs 直接查 Iceberg/Parquet",
    ),
    Claim(
        text="Prometheus 单服务器可监控 10,000+ 台机器",
        claim_kind="benchmark",
        source_type="vendor",
        subject="full_stack",
        workload="write",
        unit_defined=True,
        config_disclosed=True,
        peak_or_steady="steady",
        already_verified=False,
        note="⭐ 官方博客明确给了前提：10 秒抓取间隔 + 每主机 700 条时间线 + 80 万样本/秒",
    ),
    Claim(
        text="Prometheus 平均每个样本 1-2 字节",
        claim_kind="spec",
        source_type="vendor",
        subject="component",
        workload="compression",
        unit_defined=True,
        config_disclosed=False,
        peak_or_steady="steady",
        already_verified=True,
        note="⭐ 官方 storage 页原文（Prometheus 3.x）：官方给出的容量估算公式输入，用途明确",
    ),
    Claim(
        text="InfluxDB 3 Core 可查窗口 3 天",
        claim_kind="spec",
        source_type="vendor",
        subject="component",
        workload="query",
        unit_defined=True,
        config_disclosed=True,
        peak_or_steady="steady",
        already_verified=True,
        note="⭐ L11 已核实：432 文件 × 10min 的派生值，代码无时间判断（Core 3.11）",
    ),
    Claim(
        text="TimescaleDB hypercore 列存压缩可达 98%",
        claim_kind="benchmark",
        source_type="vendor",
        subject="component",
        workload="compression",
        unit_defined=True,
        config_disclosed=False,
        peak_or_steady="peak",
        already_verified=False,
        note="⭐ 官方 hypercore 页「up to 98%」；同页另有「more than 90%」的保守口径",
    ),
    Claim(
        text="InfluxDB 3 Core 批量写入阈值 10,000 行或 10 MB",
        claim_kind="spec",
        source_type="vendor",
        subject="component",
        workload="write",
        unit_defined=True,
        config_disclosed=True,
        peak_or_steady="steady",
        already_verified=True,
        note="⭐ L12 已核实并实测四档行长：全部是行数先到，阈值分界 1048 字节/行",
    ),
    Claim(
        text="Telegraf 插件数量 300+（官方另一处口径为 400+）",
        claim_kind="spec",
        source_type="vendor",
        subject="component",
        workload="mixed",
        unit_defined=False,
        config_disclosed=False,
        peak_or_steady="steady",
        already_verified=True,
        note="🔴 官方口径自相矛盾：文档页/产品页写 400+，GitHub README 写 over 300"
             "（⭐ 本课「冲突记录 4」）→ 保守取 300+，且不影响任何决策结论",
    ),
    Claim(
        text="Telegraf 多 URL 配置 = 双写高可用",
        claim_kind="misread",
        source_type="in_house",
        subject="component",
        workload="write",
        unit_defined=False,
        config_disclosed=True,
        peak_or_steady="unknown",
        already_verified=True,
        note="🔴 这不是基准数字，是理解错误。⭐ L16 已核实官方语义：故障转移，非双写",
    ),
]


# ============================================================
# 主流程
# ============================================================

def main() -> None:
    print("=" * 78)
    print("L17 实验 B · 基准数字口径审计器")
    print("=" * 78)
    print("\n审计六问：谁测的 → 测的什么 → 口径对齐了吗 →")
    print("          配置说清了吗 → 峰值还是稳态 → 能写进决策文档吗\n")

    counts = {"OK": 0, "WARN": 0, "BLOCK": 0}
    by_kind = {"benchmark": [0, 0, 0], "spec": [0, 0, 0], "misread": [0, 0, 0]}
    kind_name = {
        "benchmark": "性能宣称（六问全审）",
        "spec": "官方规格/硬限制（只审来源与版本）",
        "misread": "理解错误（直接判死）",
    }
    order = {"OK": 0, "WARN": 1, "BLOCK": 2}

    for i, c in enumerate(CLAIMS, 1):
        issues = audit(c)
        code, v = verdict(issues)
        counts[code] += 1
        by_kind[c.claim_kind][order[code]] += 1

        print("─" * 78)
        print(f"[{i}] {c.text}")
        print(f"    Q0 分类：{kind_name[c.claim_kind]}")
        print(f"    出处：{c.note}")
        print(f"    标签：来源={c.source_type} · 被测={c.subject} · 负载={c.workload}")
        for lv, msg in issues:
            mark = {"INFO": "ℹ️ ", "WARN": "⚠️ ", "BLOCK": "🔴"}[lv]
            print(f"    {mark} {msg}")
        print(f"    ➜ 结论：{v}")

    # ---- 汇总 ----
    print("\n" + "=" * 78)
    print("📊 审计汇总")
    print("=" * 78)
    total = len(CLAIMS)
    print(f"  共审计 {total} 条宣称：")
    print(f"    ✅ 可直接写入决策文档 : {counts['OK']} 条")
    print(f"    ⚠️ 需标注来源才能写   : {counts['WARN']} 条")
    print(f"    ❌ 禁止写入           : {counts['BLOCK']} 条")

    print("\n  按 Q0 分类拆开看（这才是关键）：")
    for k in ("benchmark", "spec", "misread"):
        ok, warn, blk = by_kind[k]
        print(f"    · {kind_name[k]:<28} ✅ {ok}  ⚠️ {warn}  ❌ {blk}")

    print("\n" + "=" * 78)
    print("📌 四条从这次审计里长出来的经验")
    print("=" * 78)
    print("  0. 【先分类，再审问 —— 本实验 v2 补上 Q0，就是被这条打脸后加的】")
    print("     把「InfluxDB Core 只能查 3 天」当成性能宣称去审，会得出")
    print("     「⚠️ 厂商自述，不能裸写」——而它其实是官方硬约束，是全课最硬的排雷依据。")
    print("     三类东西必须分治：性能宣称（六问全审）／官方规格（只审来源与版本）")
    print("     ／理解错误（验证只能证伪，一律判死）。混着审，会把约束误伤成软数字。")
    print()
    print("  1. 【厂商自述不等于假，但绝不等于可直接引用】")
    print("     VictoriaMetrics 的三条自述全部是 WARN：方向可信，数字不能裸写。")
    print("     处置办法：在自己的数据集上跑一遍，把「厂商数字」换成「我们的数字」。")
    print()
    print("  2. 【能直接写的，只剩两类：官方规格、自己实测】")
    print("     官方规格（spec）只要带版本号即可引用；自己实测需写清环境与步骤。")
    print("     ⚠️ 但注意：spec 也有翻车的时候 —— 第 10 条 Telegraf 插件数，")
    print("        官方自己就给了 300+ 和 400+ 两个口径，只能取保守值。")
    print()
    print("  3. 【up to 是上界，不是典型值】")
    print("     「up to 98% 压缩」「up to 70x」这类措辞，看到 up to 就要打折。")
    print("     做容量规划请取同页的保守口径（TimescaleDB 同页给了「more than 90%」）。")

    print("\n" + "=" * 78)
    print("🎯 落到你的决策文档：一条可直接抄的标注格式")
    print("=" * 78)
    print("  写法示例：")
    print("  ┌──────────────────────────────────────────────────────────┐")
    print("  │ 结论：VictoriaMetrics 在压缩率上优于 Prometheus          │")
    print("  │ 依据：方向性结论，源自厂商官网自述（未做第三方复现）      │")
    print("  │ ⚠️ 未采用具体倍数：官网称 7x，但测试配置未披露，          │")
    print("  │    且为厂商自述，故本方案不引用该数值做容量估算。        │")
    print("  │ 后续动作：上线前用我方真实指标回放一周，取实测压缩比。   │")
    print("  └──────────────────────────────────────────────────────────┘")
    print("\n  关键不是「能不能写数字」，而是**把不确定性一起写出来**。")


if __name__ == "__main__":
    main()
