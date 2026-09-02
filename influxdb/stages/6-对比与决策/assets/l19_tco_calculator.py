#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
L19 · 实验 B：TCO 与容量规划器（✅ 本机实跑）
==============================================

回答两个选型会上必被问、却最容易拍脑袋的问题：
  1. 这套东西到底要多少钱？（TCO 三方案对比）
  2. 这套东西到底要多大？（容量估算 + 降采样分层校验）

⚠️ 本脚本的定位纪律（沿用阶段 6 overview 的口径纪律）：
   二手基准数字差异极大，本脚本**不做性能对比**，只做**成本量级**与**容量量级**估算。
   所有数字都标依据；凡是推导出来的，一律标 📌 并在结论里提醒「必须压测校准」。

设计原则：
  1. 成本拆成「看得见的」和「看不见的」—— 后者（运维人力）常常是前者的数倍
  2. 降采样层的调度周期必须校验 —— L14 已核实：能否查得到取决于调度周期，不是精度
  3. 检查清单按场景生成 —— 通用清单等于没有清单

纯标准库，Python 3.12 实跑。
"""

from dataclasses import dataclass, field
from typing import Dict, List, Tuple

# ============================================================
# 常量区（每条都标依据）
# ============================================================

# ⭐ Cloud Serverless 官方单价（官方 influxdb-cloud-pricing 页）
PRICE_WRITE_PER_MB = 0.0025
PRICE_QUERY_PER_100 = 0.012
PRICE_STORAGE_PER_GB_HOUR = 0.002
PRICE_EGRESS_PER_GB = 0.09

HOURS_PER_MONTH = 730
PRICE_STORAGE_PER_GB_MONTH = PRICE_STORAGE_PER_GB_HOUR * HOURS_PER_MONTH  # ≈ $1.46

# ⭐ InfluxDB 容量锚点（L13 已核实官方口径）
#    10 万点/秒 × 30 天 ≈ 1 TB（典型压缩比）
ANCHOR_PPS = 100_000
ANCHOR_DAYS = 30
ANCHOR_TB = 1.0
BYTES_PER_POINT = ANCHOR_TB * 1024**4 / (ANCHOR_PPS * 86_400 * ANCHOR_DAYS)

# ⭐ Core 可查窗口（L11/L13 已核实）
CORE_QUERY_FILE_LIMIT = 432
CORE_GEN1_MINUTES = 10
CORE_MAX_QUERY_DAYS = CORE_QUERY_FILE_LIMIT * CORE_GEN1_MINUTES / (24 * 60)  # 3.0

# ⭐ L14 已核实：降采样层能否查得到取决于调度周期，不是精度
#    90 天窗口 → 调度周期必须 ≥ 5h（否则文件数超限）
#    公式：文件数 = 窗口天数 × 24 × 60 / 调度周期(分钟) ≤ 432
def max_files(days: float, interval_minutes: float) -> float:
    return days * 24 * 60 / interval_minutes

def min_interval_minutes(days: float, limit: int = CORE_QUERY_FILE_LIMIT) -> float:
    """窗口内不超限所需的最小调度周期（分钟）。"""
    return days * 24 * 60 / limit


# ⭐ 关键区分：432 上限来自 Core 的 --query-file-limit，
#    而 Enterprise / Dedicated / Clustered / Serverless 都有 compactor，
#    小文件会被持续合并 —— 它们不受 432 约束。
#    ⚠️ 曾犯过的错：把这个上限无条件套到所有方案，导致 IoT 场景被误判为
#    「最小周期需 ≥ 1216.7 分钟」。修复后按 SKU 分别校验，并把这条写进收束。
SKU_FILE_LIMIT = {
    "core":       CORE_QUERY_FILE_LIMIT,   # ⭐ 硬约束，超限报错
    "enterprise": None,                    # 有 compactor
    "serverless": None,                    # 有 compactor
    "dedicated":  None,                    # 有 compactor
    "clustered":  None,                    # 有 compactor
}

# ⭐ Enterprise 官方售卖批次（官方 license 页）
ENT_CPU_BATCHES = (8, 16, 32, 64, 128)

# ⚠️ 自托管硬件成本（本课假设，⚠️ 非官方）
#    依据：官方性能调优页给的规格锚点（4核16G / 16核64G / 64核256G）
#    ⚠️ 云主机单价随地域、时间、折扣剧烈变化，这里只给量级，必须替换为真实报价
HW_SPEC = {
    "small":  {"cores": 4,  "ram_gb": 16,  "usd_month": 60},
    "medium": {"cores": 16, "ram_gb": 64,  "usd_month": 240},
    "large":  {"cores": 64, "ram_gb": 256, "usd_month": 960},
}

# ⚠️ 对象存储单价（本课假设，取公有云标准档量级）
#    ⚠️ AWS S3 Standard 约 $0.023/GB/月；此处取 $0.023
OBJ_STORAGE_PER_GB_MONTH = 0.023

# ⚠️ 运维人力成本（本课假设）
#    ⚠️ 全自托管至少需要 0.5 FTE 常驻；托管方案 0.1 FTE
OPS_FTE_SELF = 0.5
OPS_FTE_MANAGED = 0.1
OPS_FTE_USD_MONTH = 15_000     # ⚠️ 假设：单人月成本（含社保等），请替换为本地真实值


# ============================================================
# 一、输入模型
# ============================================================

@dataclass
class Workload:
    key: str
    name: str
    points_per_sec: int
    retention_days: int          # 原始数据保留天数
    downsample: bool             # 是否做降采样
    ds_interval_minutes: int     # 降采样调度周期（分钟）
    ds_retention_days: int       # 降采样数据保留天数
    queries_per_day: int         # 每日查询次数（Grafana 面板刷新会放大这个值）
    egress_gb_month: int         # 每月出流量（GB）
    avg_bytes_per_point: float = 0.0   # 0 = 用官方锚点反推值


WORKLOADS: List[Workload] = [
    Workload(
        key="iot", name="IoT 设备遥测",
        points_per_sec=20_000, retention_days=7,
        downsample=True, ds_interval_minutes=60, ds_retention_days=365,
        queries_per_day=8_640,      # 每 10 秒刷新一个面板 = 8640 次/天
        egress_gb_month=20,
    ),
    Workload(
        key="apm", name="APM / K8s 微服务监控",
        points_per_sec=150_000, retention_days=15,
        downsample=True, ds_interval_minutes=10, ds_retention_days=180,
        queries_per_day=86_400,     # 20 个面板 × 每 10 秒刷新
        egress_gb_month=60,
    ),
    Workload(
        key="biz", name="业务指标分析",
        points_per_sec=5_000, retention_days=30,
        downsample=False, ds_interval_minutes=0, ds_retention_days=0,
        queries_per_day=2_000,
        egress_gb_month=10,
    ),
]


# ============================================================
# 二、容量估算
# ============================================================

@dataclass
class Capacity:
    raw_gb: float
    ds_gb: float
    total_gb: float
    ds_ratio: float               # 降采样压缩比（本课假设）
    ds_files: float
    ds_interval_ok: bool         # ⚠️ 保留字段：仅表示「相对 Core 的 432 上限」
    ds_min_interval: float
    ds_basis: str
    # 按 SKU 分别判定（None = 该 SKU 无此约束）
    per_sku: Dict[str, Tuple[bool, str]] = field(default_factory=dict)


def estimate_capacity(w: Workload) -> Capacity:
    bpp = w.avg_bytes_per_point or BYTES_PER_POINT
    raw_gb = w.points_per_sec * bpp * 86_400 * w.retention_days / 1024**3

    if not w.downsample:
        return Capacity(raw_gb, 0.0, raw_gb, 0.0, 0.0, True, 0.0,
                        "未做降采样")

    # ⚠️ 降采样压缩比：本课假设 1 分钟粒度 ≈ 原始 1/60 点数，
    #    但聚合后每行字段更多，实测通常在 1/20 ~ 1/50 之间；取保守 1/20
    ds_ratio = 20.0
    ds_gb = raw_gb / ds_ratio * (w.ds_retention_days / max(w.retention_days, 1))
    ds_gb = max(ds_gb, 0.0)

    files = max_files(w.ds_retention_days, w.ds_interval_minutes)
    min_iv = min_interval_minutes(w.ds_retention_days)
    ok = files <= CORE_QUERY_FILE_LIMIT

    per_sku: Dict[str, Tuple[bool, str]] = {}
    for sku_key, limit in SKU_FILE_LIMIT.items():
        if limit is None:
            per_sku[sku_key] = (True,
                f"有 compactor，小文件会被合并 —— 不受 {CORE_QUERY_FILE_LIMIT} 约束；"
                f"但文件过多仍会拖慢查询（⚠️ 量级判断，非硬约束）")
        else:
            if files <= limit:
                per_sku[sku_key] = (True,
                    f"{files:,.0f} ≤ {limit}，余量 {limit / max(files, 1):.1f}×")
            else:
                per_sku[sku_key] = (False,
                    f"{files:,.0f} > {limit} 上限 —— **查不到**（报错，不是慢）；"
                    f"最小周期需 ≥ {min_iv:.1f} 分钟")

    return Capacity(
        raw_gb, ds_gb, raw_gb + ds_gb, ds_ratio, files, ok, min_iv,
        f"降采样 {w.ds_interval_minutes}min 调度，窗口 {w.ds_retention_days} 天",
        per_sku,
    )


# ============================================================
# 三、TCO 三方案
# ============================================================

@dataclass
class TcoLine:
    item: str
    usd_month: float
    basis: str


@dataclass
class TcoResult:
    plan: str
    lines: List[TcoLine] = field(default_factory=list)

    @property
    def total(self) -> float:
        return sum(x.usd_month for x in self.lines)


def tco_serverless(w: Workload, cap: Capacity) -> TcoResult:
    """方案甲：Cloud Serverless（按量付费）"""
    r = TcoResult("甲 · Cloud Serverless（按量）")
    write_mb_month = w.points_per_sec * BYTES_PER_POINT * 86_400 * 30 / 1024**2
    r.lines.append(TcoLine(
        f"写入 {write_mb_month:,.0f} MB/月 × ${PRICE_WRITE_PER_MB}/MB",
        write_mb_month * PRICE_WRITE_PER_MB, "⭐"))
    r.lines.append(TcoLine(
        f"查询 {w.queries_per_day * 30:,} 次/月 × ${PRICE_QUERY_PER_100}/100 次",
        w.queries_per_day * 30 / 100 * PRICE_QUERY_PER_100, "⭐"))
    r.lines.append(TcoLine(
        f"存储 {cap.total_gb:,.0f} GB × ${PRICE_STORAGE_PER_GB_MONTH:.2f}/GB/月",
        cap.total_gb * PRICE_STORAGE_PER_GB_MONTH, "⭐"))
    r.lines.append(TcoLine(
        f"出流量 {w.egress_gb_month} GB × ${PRICE_EGRESS_PER_GB}/GB",
        w.egress_gb_month * PRICE_EGRESS_PER_GB, "⭐"))
    r.lines.append(TcoLine(
        f"运维人力 {OPS_FTE_MANAGED} FTE × ${OPS_FTE_USD_MONTH:,}/月",
        OPS_FTE_MANAGED * OPS_FTE_USD_MONTH, "⚠️"))
    return r


def tco_enterprise(w: Workload, cap: Capacity, cores: int) -> TcoResult:
    """方案乙：InfluxDB 3 Enterprise 自托管"""
    r = TcoResult(f"乙 · Enterprise 自托管（{cores} 核）")
    spec = HW_SPEC["small"] if cores <= 4 else (
        HW_SPEC["medium"] if cores <= 16 else HW_SPEC["large"])
    r.lines.append(TcoLine(
        f"主机 {spec['cores']} 核 / {spec['ram_gb']} GB × 1 台",
        spec["usd_month"], "⚠️"))
    r.lines.append(TcoLine(
        f"对象存储 {cap.total_gb:,.0f} GB × ${OBJ_STORAGE_PER_GB_MONTH}/GB/月",
        cap.total_gb * OBJ_STORAGE_PER_GB_MONTH, "⚠️"))
    r.lines.append(TcoLine(
        "Enterprise 商业授权（CPU 核计费，需 Contact Sales）",
        0.0, "❓"))
    r.lines.append(TcoLine(
        f"运维人力 {OPS_FTE_SELF} FTE × ${OPS_FTE_USD_MONTH:,}/月",
        OPS_FTE_SELF * OPS_FTE_USD_MONTH, "⚠️"))
    return r


def tco_core(w: Workload, cap: Capacity) -> TcoResult:
    """方案丙：InfluxDB 3 Core（开源免费，仅作对照）"""
    r = TcoResult("丙 · InfluxDB 3 Core（开源，仅对照）")
    if w.retention_days > CORE_MAX_QUERY_DAYS:
        r.lines.append(TcoLine(
            f"⚠️ 保留 {w.retention_days} 天 > Core 可查窗口 {CORE_MAX_QUERY_DAYS:.0f} 天"
            f" —— 存得下但查不到，本方案在此场景不成立", 0.0, "⭐"))
        return r
    r.lines.append(TcoLine("软件许可（MIT / Apache 2 双许可）", 0.0, "⭐"))
    spec = HW_SPEC["small"]
    r.lines.append(TcoLine(
        f"主机 {spec['cores']} 核 / {spec['ram_gb']} GB × 1 台",
        spec["usd_month"], "⚠️"))
    r.lines.append(TcoLine(
        f"对象存储 {cap.total_gb:,.0f} GB × ${OBJ_STORAGE_PER_GB_MONTH}/GB/月",
        cap.total_gb * OBJ_STORAGE_PER_GB_MONTH, "⚠️"))
    r.lines.append(TcoLine(
        f"运维人力 {OPS_FTE_SELF} FTE × ${OPS_FTE_USD_MONTH:,}/月",
        OPS_FTE_SELF * OPS_FTE_USD_MONTH, "⚠️"))
    return r


def pick_cores(w: Workload) -> int:
    """📌 核数推算（本课推导）：以官方「32 核 → 100k 点/秒」为锚点线性外推。"""
    raw = w.points_per_sec / 100_000 * 32
    for b in ENT_CPU_BATCHES:
        if raw <= b:
            return b
    return ENT_CPU_BATCHES[-1]


# ============================================================
# 四、落地检查清单（按场景生成）
# ============================================================

@dataclass
class CheckItem:
    phase: str
    text: str
    basis: str          # ⭐ / ⚠️ / 📌


def build_checklist(w: Workload, cap: Capacity) -> List[CheckItem]:
    items: List[CheckItem] = []

    # —— 阶段一：选型前（没做这些，后面全是返工） ——
    items.append(CheckItem("① 选型前",
        "写下「必须满足」与「最好有」两栏，后者一律不进决策依据", "📌"))
    items.append(CheckItem("① 选型前",
        "确认是选**产品**还是选**SKU**——两个问题分开答，别混成一次决策", "📌"))
    items.append(CheckItem("① 选型前",
        f"用真实数据压测，替换本脚本的推算值（当前每点 {BYTES_PER_POINT:.2f} B 由官方锚点反推）", "⚠️"))
    if w.retention_days > CORE_MAX_QUERY_DAYS:
        items.append(CheckItem("① 选型前",
            f"保留 {w.retention_days} 天 > Core 可查窗口 {CORE_MAX_QUERY_DAYS:.0f} 天"
            f" —— 若已选 Core，立刻停下来重新评估", "⭐"))

    # —— 阶段二：容量与降采样 ——
    if w.downsample:
        core_ok, core_msg = cap.per_sku.get("core", (True, ""))
        if not core_ok:
            items.append(CheckItem("② 容量",
                f"🔴 若选 Core：降采样 {w.ds_interval_minutes}min 会产生 {cap.ds_files:,.0f} 个文件，"
                f"超过 {CORE_QUERY_FILE_LIMIT} 上限 —— 查不到，不是慢。"
                f"最小周期需 ≥ {cap.ds_min_interval:.1f} 分钟", "⭐"))
        else:
            items.append(CheckItem("② 容量",
                f"若选 Core：降采样 {w.ds_interval_minutes}min → {cap.ds_files:,.0f} 文件"
                f"（上限 {CORE_QUERY_FILE_LIMIT}），余量 "
                f"{CORE_QUERY_FILE_LIMIT / max(cap.ds_files, 1):.1f}×", "⭐"))
        items.append(CheckItem("② 容量",
            "⚠️ 降采样层能否查得到取决于**调度周期**，不是精度（L14 已核实）——"
            "改精度救不了文件数超限", "⭐"))
        items.append(CheckItem("② 容量",
            "⚠️ 432 文件上限**只对 Core 成立**；Enterprise / Dedicated / Clustered / Serverless "
            "有 compactor 会合并小文件，不受此硬约束（但文件过多仍会拖慢查询）", "⭐"))
    items.append(CheckItem("② 容量",
        f"磁盘按 1.2 倍预留：估算 {cap.total_gb:,.0f} GB → 实际预留 "
        f"{cap.total_gb * 1.2:,.0f} GB（L18 已核实：行协议导出无压缩，导出时体积更大）", "📌"))

    # —— 阶段三：部署 ——
    items.append(CheckItem("③ 部署",
        "Docker 一律固定版本标签，**绝不用 latest**"
        "（官方全站横幅警告；且该横幅日期官方自己给了多个版本，别信任何具体日期）", "⭐"))
    items.append(CheckItem("③ 部署",
        "保留期：**永久 = 不传参数**，绝不能写 `0d`（1.x/2.x 的 0 = 永久，3.x 的 0d = 立刻全删）", "⭐"))
    items.append(CheckItem("③ 部署",
        "用 InfluxQL 查询的库名必须写成 `database_name/retention_policy_name`（DBRP 倒灌命名约定）", "⭐"))
    if w.points_per_sec > 100_000:
        items.append(CheckItem("③ 部署",
            f"写入 {w.points_per_sec:,} 点/秒 > 10 万阈值 —— 官方性能调优页建议"
            f"调高 --num-io-threads（默认仅 2，会浪费绝大部分 CPU）", "⭐"))

    # —— 阶段四：验证 ——
    items.append(CheckItem("④ 验证",
        "对账不能只 COUNT：还要抽样 10 个点、比对列顺序、核对时间边界（L18 S5）", "📌"))
    items.append(CheckItem("④ 验证",
        "双写窗口：下限 = 覆盖对账周期（1-3 天），上限 = 可查窗口"
        "（Core = 3 天）→ Core 上双写实际只有 1-3 天，对账脚本必须提前写好", "⭐"))
    items.append(CheckItem("④ 验证",
        "灰度切读：先 1 个面板跑 24h，确认无历史查询报错再全量", "📌"))

    # —— 阶段五：上线后 ——
    items.append(CheckItem("⑤ 上线后",
        "监控「有没有声音」类指标：写入成功率、查询报错率、降采样任务成功率"
        "—— 静默失败不会自己报错，只能靠这些指标兜住", "📌"))
    items.append(CheckItem("⑤ 上线后",
        "升 3.10 前：先 --version，再按 3.4.0 分界选 catalog 备份路径；"
        "⚠️ 启动 3.10 就已不可逆", "⭐"))
    items.append(CheckItem("⑤ 上线后",
        "每季度复查一次本清单的成本项 —— 按量计费的费用会随数据增长失控", "⚠️"))

    return items


# ============================================================
# 五、打印
# ============================================================

def hr(ch: str = "=", n: int = 78) -> str:
    return ch * n


def run_one(w: Workload) -> None:
    print(hr())
    print(f"负载：{w.name}   [{w.key}]")
    print(hr())
    print(f"  写入 {w.points_per_sec:,} 点/秒 ｜ 原始保留 {w.retention_days} 天 "
          f"｜ {'降采样 ' + str(w.ds_interval_minutes) + 'min / 保留 ' + str(w.ds_retention_days) + ' 天' if w.downsample else '无降采样'}")
    print(f"  查询 {w.queries_per_day:,} 次/天 ｜ 出流量 {w.egress_gb_month} GB/月")
    print()

    # --- 容量 ---
    cap = estimate_capacity(w)
    print("【容量估算】")
    print(f"  原始数据      {cap.raw_gb:>12,.1f} GB")
    if w.downsample:
        print(f"  降采样数据    {cap.ds_gb:>12,.1f} GB   （压缩比假设 1/{cap.ds_ratio:.0f}，⚠️ 需实测校准）")
    print(f"  {'─' * 20}")
    print(f"  合计          {cap.total_gb:>12,.1f} GB")
    print(f"  建议预留      {cap.total_gb * 1.2:>12,.1f} GB   （📌 1.2 倍，导出时行协议无压缩）")
    print()
    if w.downsample:
        print(f"  降采样文件数校验（{w.ds_interval_minutes}min × {w.ds_retention_days} 天 "
              f"→ {cap.ds_files:,.0f} 个文件）")
        print(f"  ⭐ 关键：这个上限**只对 Core 成立**，其他 SKU 有 compactor 会合并小文件")
        print()
        for sku_key in ("core", "enterprise", "serverless", "dedicated", "clustered"):
            okk, msg = cap.per_sku.get(sku_key, (True, ""))
            flag = "✅" if okk else "🔴"
            print(f"      {flag} {sku_key:<11} {msg}")
        print()

    # --- TCO ---
    cores = pick_cores(w)
    plans = [tco_serverless(w, cap), tco_enterprise(w, cap, cores), tco_core(w, cap)]
    print("【TCO 三方案对比（月度，USD）】")
    print()
    for p in plans:
        print(f"  {p.plan}")
        for ln in p.lines:
            amt = "—" if ln.basis == "❓" else f"${ln.usd_month:>10,.2f}"
            print(f"      [{ln.basis}] {ln.item:<56} {amt:>12}")
        note = ""
        if any(x.basis == "❓" for x in p.lines):
            note = "  （不含授权费，实际更高）"
        print(f"      {'─' * 68}")
        print(f"      月合计{'（不含授权费）' if note else ''}".ljust(74) + f"${p.total:>10,.2f}")
        print()

    # 对比结论
    valid = [p for p in plans if not any(x.basis == "⭐" and "不成立" in x.item for x in p.lines)]
    if len(valid) >= 2:
        print("  ⚠️ 先对齐口径：本表只比**成本**，不比**可行性**。")
        print("     「最省」不等于「能选」—— 可行性由实验 A 的排雷结果决定。")
        print("     例：实验 A 中 IoT 场景 Core 未被 BLOCK 但 Serverless 被 BLOCK，")
        print("         这里的成本排序不能反过来推翻那个结论。")
        print()
        valid.sort(key=lambda p: p.total)
        cheapest = valid[0]
        print(f"  → 当前假设下最省：{cheapest.plan}  ≈ ${cheapest.total:,.0f}/月")
        second = valid[1]
        if second.total > 0:
            diff = second.total - cheapest.total
            pct = diff / cheapest.total * 100
            print(f"     第二便宜：{second.plan} ≈ ${second.total:,.0f}/月（贵 {pct:.0f}%）")
        print()
        print("  ⚠️ 三条必须说清的口径：")
        print("     1. 乙方案**未含** Enterprise 商业授权费（官方 Contact Sales）")
        print("        授权按 CPU 核计费，是大额固定支出 —— 它会显著改变排序")
        print("     2. 运维人力用的是假设值，请替换为本地真实成本；")
        print("        **在中小规模下，人力常常比机器贵**")
        print("     3. 按量计费的写入/查询项会随业务增长线性放大，")
        print("        本表只反映**当前**负载，不是长期成本")
        print()

    # --- 检查清单 ---
    print("【落地检查清单（按本负载生成）】")
    print()
    cur_phase = ""
    for it in build_checklist(w, cap):
        if it.phase != cur_phase:
            cur_phase = it.phase
            print(f"  {cur_phase}")
        print(f"      [{it.basis}] {it.text}")
    print()


def main() -> None:
    print(hr("#"))
    print("L19 · 实验 B：TCO 与容量规划器")
    print("多少钱？多大？以及一份能照着执行的清单")
    print(hr("#"))
    print()
    print("依据分布：")
    print(f"  ⭐ 官方一手：Serverless 四个单价（${PRICE_WRITE_PER_MB}/MB、"
          f"${PRICE_QUERY_PER_100}/100 次、${PRICE_STORAGE_PER_GB_HOUR}/GB-hour、"
          f"${PRICE_EGRESS_PER_GB}/GB）")
    print(f"  ⭐ 官方一手：Core 可查窗口 {CORE_QUERY_FILE_LIMIT} 文件上限、"
          f"L13 官方容量锚点（10 万点/秒 × 30 天 ≈ 1 TB）")
    print(f"  ⚠️ 假设值：硬件月费、对象存储 ${OBJ_STORAGE_PER_GB_MONTH}/GB、"
          f"运维人力 ${OPS_FTE_USD_MONTH:,}/FTE/月 —— 全部需替换为真实报价")
    print(f"  📌 本课推导：每点 {BYTES_PER_POINT:.2f} B、降采样压缩比 1/20、磁盘 1.2 倍预留")
    print()
    print("  ❓ 无法获取：Enterprise 商业授权费（官方 Contact Sales，不公开报价）")
    print()

    for w in WORKLOADS:
        run_one(w)

    print(hr("#"))
    print("收束：三条选型会上必须讲清的话")
    print(hr("#"))
    print()
    print("  1. **成本排序会被授权费翻转**。本表未含 Enterprise 授权费，")
    print("     按量方案在小负载时明显便宜，但写入量涨 10 倍后，")
    print("     按量的线性增长会超过自托管的固定成本 —— 交叉点必须自己算，别抄结论。")
    print()
    print("  2. **约束是有归属的**——432 文件上限是 **Core 的属性**，不是 InfluxDB 的属性。")
    print("     本脚本初版把它无条件套到所有方案，得出「最小周期需 ≥ 1216.7 分钟」的荒谬结论。")
    print("     Enterprise / Dedicated / Clustered / Serverless 有 compactor，小文件会被合并。")
    print("     **选型时把 A 的约束套到 B 上，和把 A 的优点算到 B 头上，是同一类错误。**")
    print()
    print("  3. **降采样层查不到，是调度周期的锅，不是精度的锅**（L14 已核实）。")
    print("     在 Core 上：`10min` 调度 × 180 天 = 25,920 个文件，远超 432 上限。")
    print("     这条在上线前算一遍，比上线后查不到再救要便宜两个数量级。")
    print()
    print("  4. **清单的价值在于「按场景生成」**。通用清单等于没有清单 ——")
    print("     本脚本的每一条都挂着当前负载的具体数字，改数字清单就变。")
    print()


if __name__ == "__main__":
    main()
