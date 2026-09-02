# -*- coding: utf-8 -*-
"""
tco.py —— 成本估算（只在可行性已知的前提下比钱）

📌 回指：L13《部署形态与容量规划》、L19《场景演练与选型决策》

⚠️ L19 的 P0-2 修复点：本模块**只比成本，不比可行性**。
   可行性由 decision.py 的排雷结果决定 ——「最省」不等于「能选」。
   Enterprise 商业授权费官方不公开，本模块**不估算**它（标 ❓），
   因此下面的 Enterprise 成本是**不含授权费的下限**。
"""

from config import (
    HOURS_PER_MONTH, OBJ_STORAGE_PER_GB_MONTH, OPS_FTE_MANAGED, OPS_FTE_SELF,
    OPS_FTE_USD_MONTH, PRICE_HOST_SELF, PRICE_STORAGE_PER_GB_MONTH,
    PRICE_WRITE_PER_MB, Finding, Workload,
)
from engine import fmt, stored_bytes


def serverless_cost(w: Workload, stored_gb: float, written_gb_month: float) -> dict:
    """⭐ Serverless 四个官方单价：写入 / 查询 / 存储 / 出流量。"""
    write = written_gb_month * 1024 * PRICE_WRITE_PER_MB
    storage = stored_gb * PRICE_STORAGE_PER_GB_MONTH
    return {
        "sku": "Cloud Serverless",
        "写入": write,
        "查询": 0.0,          # 由 dashboard 频率决定，单独算，见 ops.py
        "存储": storage,
        "出流量": 0.0,        # 无出流量假设，不估算
        "主机": 0.0,
        "运维人力": OPS_FTE_MANAGED * OPS_FTE_USD_MONTH,
    }


def core_cost(w: Workload, stored_gb: float) -> dict:
    """自托管 Core：主机 + 对象存储 + 运维人力。"""
    return {
        "sku": "Core（自托管）",
        "写入": 0.0,
        "查询": 0.0,
        "存储": stored_gb * OBJ_STORAGE_PER_GB_MONTH,
        "出流量": 0.0,
        "主机": PRICE_HOST_SELF,      # ⚠️ 假设值，来自 config
        "运维人力": OPS_FTE_SELF * OPS_FTE_USD_MONTH,
    }


def run(w: Workload) -> list:
    out = []
    stored = stored_bytes(w.pps, w.raw_retention_days)
    stored_gb = stored / 1024 ** 3
    written_gb_month = (w.pps * 86_400 * 30 * 120) / 1024 ** 3

    out.append(Finding(
        "INFO", "阶段 6 · L19",
        "⚠️ 口径对齐：下面只比**成本**，不比**可行性**",
        "「最省」不等于「能选」。可行性由 decision.py 的排雷结果决定 —— "
        "被排除的 SKU 再便宜也不能选。",
        "先看排雷结果，再看这张成本表",
    ))

    plans = [core_cost(w, stored_gb), serverless_cost(w, stored_gb, written_gb_month)]

    lines = []
    for p in plans:
        parts = {k: v for k, v in p.items() if k != "sku"}
        total = sum(parts.values())
        # 📌 自校验：分项之和必须等于总数（L19 教过的教训 —— 让脚本自己报出不一致）
        shown = " + ".join(f"{k} ${v:,.0f}" for k, v in parts.items() if v > 0)
        assert abs(sum(v for v in parts.values()) - total) < 1e-6
        lines.append(f"{p['sku']} ≈ ${total:,.0f}/月（{shown}）")
        if p["写入"] > total * 0.5:
            lines.append("    ⚠️ 写入费占比 {:.0%} —— 这个场景的成本大头是写入量，"
                         "优化方向是降采样与采样率，不是换 SKU".format(p["写入"] / total))

    out.append(Finding(
        "INFO", "阶段 6 · L19",
        f"月度成本对比（保留 {w.raw_retention_days} 天，存储约 {fmt(stored)}）",
        " | ".join(lines),
        "把 OPS_FTE_USD_MONTH 与 HOST_USD_MONTH 换成你的真实人力与主机成本",
    ))

    # ⭐ L19 核心结论之一：运维人力常常比机器贵
    host = PRICE_HOST_SELF
    ops = OPS_FTE_SELF * OPS_FTE_USD_MONTH
    ratio = ops / host if host else float("inf")
    out.append(Finding(
        "P1", "阶段 6 · L19",
        f"自托管的运维人力是主机费的 {ratio:.0f} 倍",
        f"运维 ${ops:,.0f}/月 vs 主机 ${host:,.0f}/月。"
        "📌 这意味着「为了省托管费而自托管」在人力充足时成立、在人力紧张时不成立。",
        "算成本时把人力算进去；只比机器钱的表格必然导向错误的结论",
    ))

    out.append(Finding(
        "P0", "阶段 6 · L19",
        "Enterprise 授权费未计入 —— 它是可能翻转排序的隐藏项",
        "❓ Enterprise 商业授权费官方不公开，本模块不估算。"
        "Trial（256 核 / 30 天）与 At-Home（2 核 / 单节点）都**不可商用**。"
        "⚠️ 拿到报价后重跑本表，排序可能变。",
        "找销售拿报价，别用本表的 Enterprise 数字做预算",
    ))

    out.append(Finding(
        "P2", "阶段 6 · L19",
        "Core → Enterprise 无需搬数据，但反向不被支持",
        "⭐ Downgrading is not supported。这是一道单向门：可以先上 Core 再升 Enterprise，"
        "但升上去就回不来了。",
        "若未来可能长期停留在 Core，先确认 Core 的 3 天可查窗口能接受",
    ))
    return out
