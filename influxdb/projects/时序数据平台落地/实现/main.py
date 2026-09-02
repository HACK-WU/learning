# -*- coding: utf-8 -*-
"""
main.py —— 《时序数据平台落地体检器》主入口

用法：
    python3 main.py            # 跑全部三份预设负载
    python3 main.py iot        # 只跑指定场景（iot / k8s / biz）

设计要点（对应 设计决策.md 的决策 2 / 3）：
  · 每个模块返回统一的 Finding 列表，主程序负责排序与汇总（开闭原则）
  · 所有常量来自 config.py，模块间不重复定义（单一数据源）
  · P0/P1 有阻断语义：退出码非 0 表示这份负载还不能上生产

退出码：
    0 = 无 P0 无 P1        1 = 有 P0        2 = 只有 P1
"""

import sys

import config
import decision
import engine
import ops
import schema_design
import tco

MODULES = [
    ("阶段 3 · 数据模型", schema_design),
    ("阶段 4 · 存储引擎", engine),
    ("阶段 5 · 生产落地", ops),
    ("阶段 6 · 对比决策", decision),
    ("成本估算", tco),
]


def hr(ch: str = "=", n: int = 78) -> str:
    return ch * n


def run_one(w: config.Workload) -> tuple:
    """跑一个场景，返回 (findings, 统计字典)。

    ⚠️ 两阶段顺序不能反：**先排雷，再体检**。
       排雷得出幸存 SKU 后，engine / ops 才能按「约束归属」判断该不该报 Core 专属约束 ——
       否则会出现「一边说 Core 不能用，一边说 Core 查不到」的自相矛盾。
    """
    # ---- 阶段一：选品排雷（L17 / L18 / L19）-------------------------
    decision_findings = decision.run(w)
    survivors = decision.surviving_skus(w)

    # ---- 阶段二：按幸存 SKU 做工程体检 ------------------------------
    findings = list(decision_findings)
    for label, mod in MODULES:
        if mod is decision:
            continue                     # 已在阶段一跑过
        try:
            findings.extend(mod.run(w, allowed_skus=survivors))
        except TypeError:
            findings.extend(mod.run(w))  # 不需要 SKU 上下文的模块（schema / tco）

    order = config.LEVEL_ORDER
    findings.sort(key=lambda f: order.get(f.level, 9))

    stat = {"P0": 0, "P1": 0, "P2": 0, "INFO": 0}
    for f in findings:
        stat[f.level] = stat.get(f.level, 0) + 1

    print(hr())
    print(f"场景：{w.name}")
    print(f"负载：{w.pps:,} 点/秒 · 保留 {w.raw_retention_days} 天 · "
          f"要求可查 {w.query_window_days} 天")
    print(f"基数：{w.series:,} series · 点密度 {w.point_density:.4f}")
    if w.source_version != "none":
        print(f"迁移来源：InfluxDB {w.source_version}")
    print(f"幸存 SKU：{' / '.join(survivors) if survivors else '无（约束本身有问题）'}")
    print(hr())

    for f in findings:
        mark = {"P0": "🔴", "P1": "🟡", "P2": "⚪", "INFO": "ℹ️ "}[f.level]
        print(f"\n{mark} [{f.level}] {f.title}")
        print(f"   归属：{f.stage}")
        if f.detail:
            for line in f.detail.split(" | "):
                print(f"   {line}")
        if f.action:
            print(f"   → 建议：{f.action}")

    print("\n" + hr("-"))
    print(f"小计：P0={stat['P0']}  P1={stat['P1']}  P2={stat['P2']}  INFO={stat['INFO']}")
    if stat["P0"]:
        print("结论：🔴 存在阻断项 —— 这份负载按当前设计不能上生产，先解决 P0")
    elif stat["P1"]:
        print("结论：🟡 无阻断项，但有需要决策的风险点")
    else:
        print("结论：✅ 无阻断项")
    print()

    return findings, stat


def main() -> int:
    args = sys.argv[1:]
    if args:
        keys = [k for k in args if k in config.WORKLOADS]
        if not keys:
            print(f"未知场景 {args}。可选：{', '.join(config.WORKLOADS)}")
            return 3
        selected = [config.WORKLOADS[k] for k in keys]
    else:
        selected = list(config.WORKLOADS.values())

    total = {"P0": 0, "P1": 0, "P2": 0, "INFO": 0}
    for w in selected:
        _, stat = run_one(w)
        for k, v in stat.items():
            total[k] += v

    print(hr())
    print("全部场景汇总")
    print(hr())
    print(f"P0={total['P0']}  P1={total['P1']}  P2={total['P2']}  INFO={total['INFO']}")
    print()
    print("⚠️ 口径提醒：")
    print("  · 标 ⭐ 的条目来自官方一手文档，标 ⚠️ 的是假设值，标 📌 的是本课推导")
    print("  · 压缩比、人力成本、主机价格都是假设，请替换为实测值再用于决策")
    print("  · Enterprise 授权费不公开，本工具不估算，排序可能被它翻转")
    print()

    if total["P0"]:
        return 1
    if total["P1"]:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
