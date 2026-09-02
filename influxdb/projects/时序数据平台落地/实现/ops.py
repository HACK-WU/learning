# -*- coding: utf-8 -*-
"""
ops.py —— 阶段 5 体检（L13 部署 / L14 降采样与保留 / L15 处理引擎 / L16 生态）

📌 回指：L13《部署形态与容量规划》、L14《降采样、保留策略与成本》、
        L15《处理引擎》、L16《生态集成：Telegraf、Grafana 与自监控》

本模块回答三个问题：
  1. 降采样层的调度周期能不能让它在 Core 上被查到
  2. 保留期写法会不会踩「0d 反转」或「mo 非日历」这两个静默坑
  3. Telegraf / Grafana 配置有没有踩 L16 的四条硬约束
"""

from config import (
    CALENDAR_MONTH_DAYS, FILES_PER_DAY, HOURS_PER_MONTH, PRICE_QUERY_PER_100,
    SKU_FILE_LIMIT, UNIT_DAYS, Finding, Workload,
)


# ===== L14：降采样与保留期 ==========================================

def check_downsample(w: Workload, allowed_skus: list = None) -> list:
    """⭐ L14 核心结论：降采样层能否查到，取决于调度周期而不是精度。

    allowed_skus：Core 已被排除时不再报 Core 专属的 432 约束（约束归属原则）。
    """
    out = []
    limit = SKU_FILE_LIMIT.get("core")
    if limit is None:
        return out
    if allowed_skus is not None and "core" not in allowed_skus:
        out.append(Finding(
            "INFO", "阶段 5 · L14",
            "降采样调度周期检查跳过 —— Core 已被排雷排除",
            "📌 约束归属：调度周期与 432 文件上限的换算只在 Core 上有意义。"
            "当前候选 SKU 都有 compactor，降采样层不受此约束。",
            "若最终又选回 Core，请重跑本项",
        ))
        return out

    horizon = w.query_window_days
    interval_h = w.downsample_interval_min / 60
    files = horizon * 24 / interval_h

    out.append(Finding(
        "INFO", "阶段 5 · L14",
        f"降采样层：每 {w.downsample_interval_min} 分钟聚一次，回溯 {horizon} 天",
        f"⭐ 文件数 = 窗口天数 × 24 × 60 ÷ 调度周期(分钟) = {files:,.0f} 个。"
        "注意这个公式里没有精度 —— 存 1 分钟精度和存 1 小时精度，文件数一样。",
        "拿这个数对照下一条",
    ))

    if files > limit:
        min_interval = horizon * 24 * 60 / limit
        out.append(Finding(
            "P0", "阶段 5 · L14",
            f"降采样层 {files:,.0f} 文件 > Core 上限 {limit} → 这层数据查不到",
            f"要在 Core 上把 {horizon} 天纳入可查范围，调度周期必须 ≥ {min_interval:.0f} 分钟"
            f"（≈ {min_interval / 60:.1f} 小时）。当前 {w.downsample_interval_min} 分钟太密。",
            f"把调度周期放宽到 {int(min_interval) + 1} 分钟以上，或换有 compactor 的 SKU",
        ))
    else:
        out.append(Finding(
            "INFO", "阶段 5 · L14",
            f"降采样层 {files:,.0f} 文件 ≤ Core 上限 {limit} ✅",
            "这层可以在 Core 上正常查询。",
            "继续保留该调度周期",
        ))
    return out


def parse_retention(expr: str):
    """解析保留期写法，返回 (数值, 单位, 天数)。解析不了返回 None。"""
    expr = (expr or "").strip()
    for unit in ("mo", "ms", "m", "h", "d", "w", "y"):
        if expr.endswith(unit):
            head = expr[: -len(unit)]
            try:
                n = float(head)
            except ValueError:
                return None
            if unit == "ms":          # ⭐ 官方不支持 ms（毫秒）—— 最小 1h
                return (n, unit, None)
            return (n, unit, n * UNIT_DAYS.get(unit, 0))
    return None


def check_retention(w: Workload) -> list:
    """⭐ L14：0d 语义反转（reverse · 灾难级）+ mo 非日历（drift · 合规级）。

    📌 本函数按**实际写的保留期**做检测，而不是无条件告警 ——
       无条件告警会把「写对了的人」也淹在 P0 里，等于没有信号。
    """
    out = []
    parsed = parse_retention(w.retention_period)

    if parsed is None:
        out.append(Finding(
            "P1", "阶段 5 · L14",
            f"保留期写法「{w.retention_period}」无法解析",
            "⭐ 官方支持的单位：h / d / w / mo / y。⚠️ 不支持 m（分钟）与 s（秒），"
            "ms 也不支持，最短保留期是 1h。",
            "按官方单位重写保留期",
        ))
        return out

    n, unit, days = parsed

    # ① reverse：0d 语义反转 —— 灾难级
    if n == 0:
        out.append(Finding(
            "P0", "阶段 5 · L14",
            f"保留期写了 {w.retention_period} —— 在 3.x 里这是**立刻全删**，不是永久",
            "⭐ 3.x 与 1.x/2.x 语义相反：老版本 0d = 永久保留，3.x 0d = 立刻删除。"
            "这是 L18 归类的 reverse 型静默 —— 方向反了，灾难级，"
            "数据会在后台 retention-check-interval（默认 30m）触发时被真删，且**没有任何报错**。",
            "立即改成具体时长（如 90d）；建库后 SHOW DATABASES 确认不是 0d；"
            "从 1.x/2.x 迁过来的脚本必须逐条改",
        ))
    elif unit in ("mo", "y"):
        # ③ drift：非日历单位 —— 幅度偏了
        want_days = n * (CALENDAR_MONTH_DAYS if unit == "mo" else 365.25)
        diff = abs(want_days - days)
        # 📌 判据用**相对偏差**而非绝对天数：1y 差 0.2 天（0.05%）不该比 3mo 差 1.3 天（1.4%）更严重
        rel = diff / want_days if want_days else 0.0
        material = rel >= 0.003          # 偏差 ≥ 0.3% 视为实质偏差
        level = "P0" if (w.compliance and material) else "P1"
        if w.compliance and material:
            tag = f"（本场景有合规要求且偏差 {rel:.2%} ≥ 0.3%，判 P0）"
        elif w.compliance:
            tag = f"（有合规要求，但偏差仅 {rel:.2%} < 0.3%，判 P1）"
        else:
            tag = ""
        out.append(Finding(
            level, "阶段 5 · L14",
            f"保留期 {w.retention_period} = {days:.0f} 天，与「{n:g} 个自然{'月' if unit == 'mo' else '年'}」差 {diff:.1f} 天（{rel:.2%}）{tag}",
            f"⭐ 官方单位：mo = 30 天、y = 365 天，都不是日历单位。"
            f"你想留的 {want_days:.1f} 天实际只留 {days:.0f} 天。"
            "这是 L18 归类的 drift 型静默 —— 幅度偏了，数据不会丢但留不够。",
            f"有合规要求的场景按天写（{want_days:.0f}d），不要用 mo / y",
        ))
    else:
        out.append(Finding(
            "INFO", "阶段 5 · L14",
            f"保留期 {w.retention_period} = {days:.1f} 天 ✅ 无单位陷阱",
            "h / d / w 都是精确单位，不存在日历偏差。",
            "保持当前写法",
        ))

    # ② 保留期是数据库级 —— 分层必须独立建库
    out.append(Finding(
        "INFO", "阶段 5 · L14",
        "保留期是数据库级的，每层分辨率必须独立建库",
        "⭐ 表级保留期是 Enterprise 3.2+ 的能力。Core 上想让原始层留 7 天、小时层留 1 年，"
        "必须建两个库（官方博客的三库方案：mqtt 90d / power_1h 1y / power_1d 10y）。",
        f"当前场景计划建 {w.databases} 个库 —— 对照 Core 上限 5 确认够用",
    ))
    return out


# ===== L16：Telegraf / Grafana ======================================

def check_telegraf(w: Workload, allowed_skus: list = None) -> list:
    """⭐ L16 四条硬约束：插件版本 / 多 URL 语义 / database_tag 基数 / organization 空串。

    database_tag 的「撞 5 库上限」只在 Core 上是问题 —— 同样遵守约束归属原则。
    """
    out = []
    tg = w.telegraf
    if not tg:
        return out

    plugin = str(tg.get("plugin", ""))
    urls = tg.get("urls") or []

    # ① 插件版本门槛
    if plugin == "outputs.influxdb_v3":
        out.append(Finding(
            "P1", "阶段 5 · L16",
            "outputs.influxdb_v3 需要 Telegraf ≥ v1.38.0",
            "⭐ 该插件自 v1.38.0 引入，更早版本写 Core 只能用 influxdb_v2 插件。",
            "确认 Telegraf 版本；不够就升级，或改用 v2 插件 + organization 空串",
        ))

    # ② 多 URL = 故障转移，不是双写也不是负载均衡
    if len(urls) > 1:
        out.append(Finding(
            "P0", "阶段 5 · L16",
            f"配了 {len(urls)} 个 URL —— 这是故障转移，不是双写",
            "⭐ 官方语义：每次 flush 随机挑一个可用 URL。数据只会落在其中一个实例上，"
            "另一个不会有副本。",
            "要冗余就得在服务端做（Enterprise 复制），别指望 Telegraf 多 URL 当副本用",
        ))

    # ③ database_tag 的目标库数 = 该 tag 的去重值个数
    if "database_tag" in tg:
        tag = str(tg["database_tag"])
        card = w.tags.get(tag)
        if card is None:
            out.append(Finding(
                "P1", "阶段 5 · L16",
                f"database_tag 指向的「{tag}」不在 tag 列表里",
                "无法估算目标库数量，也就无法判断会不会撞 Core 的 5 库上限。",
                "补到 tag 基数表里，或确认为固定值",
            ))
        else:
            core_only = allowed_skus is not None and allowed_skus == ["core"]
            if card > 5 and (allowed_skus is None or "core" in allowed_skus):
                out.append(Finding(
                    "P0", "阶段 5 · L16",
                    f"database_tag = 「{tag}」→ 会写出 {card:,} 个库，撞 Core 的 5 库上限",
                    f"⭐ 目标库数 = 该 tag 的去重值个数。{card:,} 个取值意味着 {card:,} 个数据库，"
                    "Core 上限是 5。",
                    "去掉 database_tag 改用单库多表；或换 SKU；或把该 tag 的基数压到 5 以内",
                ))
            else:
                out.append(Finding(
                    "P2", "阶段 5 · L16",
                    f"database_tag = 「{tag}」→ 会写出 {card:,} 个库",
                    f"⭐ 目标库数 = 该 tag 的去重值个数。当前候选 SKU 不受 Core 的 5 库限制，"
                    f"但 {card:,} 个库仍会带来元数据与运维复杂度。",
                    "确认这是有意为之的分库设计，而非误配",
                ))

    # ④ influxdb_v2 写 Core 时 organization 必须为空串
    if plugin == "outputs.influxdb_v2":
        org = str(tg.get("organization", ""))
        if org and (allowed_skus is None or "core" in allowed_skus):
            out.append(Finding(
                "P0", "阶段 5 · L16",
                f"influxdb_v2 插件写 Core 时 organization 必须是空串（当前为「{org}」）",
                "⭐ Core 没有 organization 概念，非空值会导致写入失败。",
                '改成 organization = ""',
            ))
        elif org:
            out.append(Finding(
                "P1", "阶段 5 · L16",
                f"influxdb_v2 插件配了 organization = 「{org}」",
                "⭐ 该字段对 Core 是致命的（必须空串），对其他形态则是必需的。"
                "当前 Core 已被排雷排除，但**若最终选回 Core 这条会变成 P0**。",
                "确认目标形态后再定；把这条留在清单里，别因为现在不是 P0 就删掉",
            ))
    return out


def check_grafana(w: Workload) -> list:
    """⭐ L16：Grafana 要选 Enterprise；面板刷新频率直接决定 Serverless 账单。"""
    out = []
    if not w.dashboard_panels or not w.dashboard_refresh_s:
        return out

    out.append(Finding(
        "INFO", "阶段 5 · L16",
        "Grafana 数据源的 Product 要选 InfluxDB Enterprise 3.x",
        "⭐ 官方原话：'currently, no Core menu option'。选错了连不上，别去找 Core 选项。",
        "按此配置数据源",
    ))

    qpm = w.dashboard_panels * (60 / w.dashboard_refresh_s)
    qpm_month = qpm * 60 * HOURS_PER_MONTH
    # ⭐ 单价来自 config（Serverless 官方 $0.012 / 100 次查询），不在此处硬编码
    cost = qpm_month / 100 * PRICE_QUERY_PER_100

    out.append(Finding(
        "P1", "阶段 6 · L19",
        f"{w.dashboard_panels} 个面板 × {w.dashboard_refresh_s}s 刷新 = {qpm_month:,.0f} 次查询/月",
        f"按 Serverless 官方单价 ${PRICE_QUERY_PER_100} / 100 次查询，仅面板刷新就是 ${cost:,.2f}/月。"
        "⚠️ 每面板按 1 个 query 估（对齐 L16 的官方算例口径）；若每面板 5 个 query 要乘 5。"
        f"（换算：{w.dashboard_refresh_s}s 单面板单 query = "
        f"{86_400 / w.dashboard_refresh_s * 30:,.0f} 次/月）",
        "把非关键面板的刷新降到 5 分钟以上；这是 Serverless 账单里最容易失控的一项",
    ))
    return out


def run(w: Workload, allowed_skus: list = None) -> list:
    return (check_downsample(w, allowed_skus) + check_retention(w)
            + check_telegraf(w, allowed_skus) + check_grafana(w))
