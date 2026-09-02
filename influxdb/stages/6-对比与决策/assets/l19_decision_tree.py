#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
L19 · 实验 A：选型决策树引擎（✅ 本机实跑）
=============================================

把「哪个更好」翻译成「在我的约束下，哪个总成本最低」。

与 L17 实验 A 的分工：
  · L17 打分器  —— 在**五款不同产品**之间打分排序（横向对比）
  · L19 决策树  —— 在**给定约束**下走判断路径，先排雷、再选 SKU、最后算钱
                   （纵向决策，且覆盖 InfluxDB 自己的五个 SKU）

⚠️ 本脚本最关键的设计：**「产品选型」和「SKU 选型」是两次独立决策**。
   很多人把它们混成一次，结果就是「我们选了 InfluxDB」这句话本身没有信息量
   —— InfluxDB 有五个 SKU，选错 SKU 的后果和选错产品一样严重。

设计原则（三条）：
  1. 先排雷再打分 —— 硬不满足的标 BLOCKED，不参与排序（沿用 L17 原则）
  2. 决策路径可追溯 —— 每一步都打印「因为什么约束，所以走到这里」
  3. 数字分三类 —— ⭐ 官方一手 / ⚠️ 厂商自述或推算 / 📌 本课推导

纯标准库，Python 3.12 实跑。
"""

from dataclasses import dataclass, field
from typing import Callable, Dict, List, Tuple

# ============================================================
# 常量区（每条都标依据，改代码前先改依据）
# ============================================================

# ⭐ Core 可查窗口 = 432 文件 × gen1 10min = 3 天（L11/L13 已核实官方 config-options）
#    AWS 官方 FAQ 独立印证："Historical queries: Limited (~3 days)"
#    "query performance degrades as data ages"（无 compactor，小文件累积）
INFLUX_CORE_QUERY_FILE_LIMIT = 432
INFLUX_CORE_GEN1_MINUTES = 10
INFLUX_CORE_MAX_QUERY_DAYS = (
    INFLUX_CORE_QUERY_FILE_LIMIT * INFLUX_CORE_GEN1_MINUTES
) / (24 * 60)  # = 3.0

# ⭐ Core 硬限制（官方 Core 页，L6 已核实）
CORE_MAX_DATABASES = 5
CORE_MAX_TABLES = 2000
CORE_MAX_COLUMNS = 500

# ⭐ Enterprise 容量（官方博客 upgrading-influxdb-3-enterprise 页）
#    "Support for 100+ databases, 10k+ tables"
#    ⚠️ 这条来自官方博客而非文档页，官方写「100+」—— 保守取其字面下限
ENT_MIN_DATABASES = 100
ENT_MIN_TABLES = 10_000

# ⭐ Enterprise 许可证类型（官方 enterprise/admin/license 页原文对照表）
#    CPU Core Limit / Expiration / Multi-node / Commercial use
#    Trial   : 256 核 / 30 天 / 支持多节点 / 不可商用
#    At-Home :   2 核 / 永不  / 仅单节点   / 不可商用
#    Commercial: 按合同
LICENSE_SPEC = {
    "Trial":      {"cpu": 256, "days": 30, "multi_node": True,  "commercial": False},
    "At-Home":    {"cpu": 2,   "days": None, "multi_node": False, "commercial": False},
    "Commercial": {"cpu": None, "days": None, "multi_node": True,  "commercial": True},
}

# ⭐ 商业授权按 CPU 核批量购买（官方 license 页原文）
#    "CPU cores are purchased in batches of 8, 16, 32, 64, or 128 cores"
#    "The CPU limit is per cluster, not per machine"
ENT_CPU_BATCHES = (8, 16, 32, 64, 128)

# ⭐ Cloud Serverless 官方定价（官方 influxdb-cloud-pricing 页四个单价）
#    写入 $0.0025/MB ｜ 查询 $0.012/100 次 ｜ 存储 $0.002/GB-hour ｜ 出流量 $0.09/GB
SRV_PRICE_WRITE_PER_MB = 0.0025
SRV_PRICE_QUERY_PER_100 = 0.012
SRV_PRICE_STORAGE_PER_GB_HOUR = 0.002
SRV_PRICE_EGRESS_PER_GB = 0.09

# ⭐ Cloud Serverless 免费层额度（官方定价页 Scale 表）
#    写入 5MB/5min ｜ 查询 300MB/5min ｜ 保留 30 天 ｜ 库 2 个
SRV_FREE = {
    "write_mb_per_5min": 5,
    "query_mb_per_5min": 300,
    "retention_days": 30,
    "databases": 2,
}

# 📌 本课推导：存储单价折成月费（730 小时/月，官方按 GB-hour 计价）
HOURS_PER_MONTH = 730
SRV_STORAGE_PER_GB_MONTH = SRV_PRICE_STORAGE_PER_GB_HOUR * HOURS_PER_MONTH  # ≈ $1.46

# ⭐ InfluxDB 容量锚点（L13 已核实）：10 万点/秒 × 30 天 ≈ 1 TB（典型压缩比）
#    ⚠️ 反推出来的「每点字节数」是从官方锚点推导，非官方直接给出的数字
ANCHOR_POINTS_PER_SEC = 100_000
ANCHOR_DAYS = 30
ANCHOR_TB = 1.0
BYTES_PER_POINT = (
    ANCHOR_TB * 1024**4 / (ANCHOR_POINTS_PER_SEC * 86_400 * ANCHOR_DAYS)
)

# ============================================================
# 一、InfluxDB 五个 SKU 的官方事实表
# ============================================================

@dataclass
class Sku:
    key: str
    name: str
    # 官方事实
    single_node_only: bool          # 是否只能单节点
    has_compactor: bool             # 是否有 compactor（决定长程查询）
    max_query_days: float           # 可查窗口上限，None = 无此限制
    has_ha: bool
    has_read_replica: bool
    has_certification: bool         # ISO 27001 / SOC 2
    has_native_v3_write: bool       # 原生 v3 写 API
    has_processing_engine: bool
    managed: bool                   # 是否全托管
    metered: bool                   # 是否按量计费
    free_tier: bool
    note: str

SKUS: Dict[str, Sku] = {
    "core": Sku(
        key="core", name="InfluxDB 3 Core",
        single_node_only=True, has_compactor=False,
        max_query_days=INFLUX_CORE_MAX_QUERY_DAYS,
        has_ha=False, has_read_replica=False, has_certification=False,
        has_native_v3_write=True, has_processing_engine=True,
        managed=False, metered=False, free_tier=True,
        note="MIT / Apache 2 双许可；官方定位「non-production, edge, or single-node」",
    ),
    "enterprise": Sku(
        key="enterprise", name="InfluxDB 3 Enterprise",
        single_node_only=False, has_compactor=True,
        max_query_days=None,
        has_ha=True, has_read_replica=True, has_certification=True,
        has_native_v3_write=True, has_processing_engine=True,
        managed=False, metered=False, free_tier=False,
        note="自托管；按 CPU 核授权（按集群不按机器）；官方定位「new production workloads」",
    ),
    "serverless": Sku(
        key="serverless", name="InfluxDB Cloud Serverless",
        single_node_only=True, has_compactor=True,
        max_query_days=None,
        has_ha=False, has_read_replica=False, has_certification=True,
        has_native_v3_write=False, has_processing_engine=False,
        managed=True, metered=True, free_tier=True,
        note="⚠️ 官方明说：无原生 v3 写 API、无 Processing Engine；多租户按量付费",
    ),
    "dedicated": Sku(
        key="dedicated", name="InfluxDB Cloud Dedicated",
        single_node_only=False, has_compactor=True,
        max_query_days=None,
        has_ha=True, has_read_replica=True, has_certification=True,
        has_native_v3_write=True, has_processing_engine=True,
        managed=True, metered=False, free_tier=False,
        note="单租户托管；私有网络与 SAML/SSO 均为附加项（官方定价页标注 add-on）",
    ),
    "clustered": Sku(
        key="clustered", name="InfluxDB Clustered",
        single_node_only=False, has_compactor=True,
        max_query_days=None,
        has_ha=True, has_read_replica=True, has_certification=True,
        has_native_v3_write=True, has_processing_engine=True,
        managed=False, metered=False, free_tier=False,
        note="K8s 自建高可用集群；官方定位「on your own infrastructure」",
    ),
}

# ============================================================
# 二、场景约束
# ============================================================

@dataclass
class Scenario:
    key: str
    name: str
    retention_days: int        # 需要保留多久（天）
    points_per_sec: int        # 写入速率（点/秒）
    databases: int
    tables: int
    need_ha: bool              # 是否需要高可用
    need_long_range: bool      # 是否需要查全量历史（超出近期窗口）
    need_compliance: bool      # 是否需要 SOC 2 / ISO 27001
    need_native_v3_api: bool   # 是否必须用原生 v3 写 API
    need_processing_engine: bool
    want_managed: bool         # 是否希望全托管（不想自己运维）
    commercial: bool           # 是否商用
    edge: bool                 # 是否边缘 / 资源受限
    ops_headcount: int         # 可投入的运维人力
    join_heavy: bool           # 是否 JOIN 密集（影响跨产品选型，不影响 SKU）

SCENARIOS: List[Scenario] = [
    Scenario(
        key="iot", name="IoT 设备遥测（边缘 + 中心）",
        retention_days=7, points_per_sec=20_000, databases=2, tables=40,
        need_ha=False, need_long_range=False, need_compliance=False,
        need_native_v3_api=True, need_processing_engine=True,
        want_managed=False, commercial=True, edge=True, ops_headcount=1,
        join_heavy=False,
    ),
    Scenario(
        key="apm", name="APM / K8s 微服务监控",
        retention_days=15, points_per_sec=150_000, databases=3, tables=120,
        need_ha=True, need_long_range=True, need_compliance=False,
        need_native_v3_api=True, need_processing_engine=True,
        want_managed=False, commercial=True, edge=False, ops_headcount=3,
        join_heavy=False,
    ),
    Scenario(
        key="biz", name="业务指标分析（需 JOIN 维表）",
        retention_days=730, points_per_sec=5_000, databases=6, tables=80,
        need_ha=True, need_long_range=True, need_compliance=True,
        need_native_v3_api=False, need_processing_engine=False,
        want_managed=True, commercial=True, edge=False, ops_headcount=2,
        join_heavy=True,
    ),
    Scenario(
        key="hybrid", name="混合负载（设备 + 业务，小团队）",
        retention_days=90, points_per_sec=30_000, databases=4, tables=300,
        need_ha=False, need_long_range=True, need_compliance=False,
        need_native_v3_api=True, need_processing_engine=True,
        want_managed=True, commercial=True, edge=False, ops_headcount=1,
        join_heavy=False,
    ),
]

# ============================================================
# 三、排雷规则（硬约束，命中即 BLOCKED）
# ============================================================

@dataclass
class Blocker:
    sku_key: str
    reason: str
    basis: str      # ⭐ / ⚠️ / 📌


def find_blockers(sc: Scenario) -> List[Blocker]:
    """对五个 SKU 逐条跑硬约束。命中 = 该 SKU 在此场景下不可选。"""
    out: List[Blocker] = []

    def blk(sku_key: str, reason: str, basis: str) -> None:
        out.append(Blocker(sku_key, reason, basis))

    # --- Core 专属硬约束 ---
    if sc.retention_days > INFLUX_CORE_MAX_QUERY_DAYS and sc.need_long_range:
        blk("core",
            f"需查全量历史 {sc.retention_days} 天 > Core 可查窗口 {INFLUX_CORE_MAX_QUERY_DAYS:.0f} 天"
            f"（{INFLUX_CORE_QUERY_FILE_LIMIT} 文件 × {INFLUX_CORE_GEN1_MINUTES}min，超限是报错不是慢）",
            "⭐")
    if sc.need_ha:
        blk("core", "需要高可用，而 Core 官方定位为 single-node（无多节点、无 HA）", "⭐")
    if sc.databases > CORE_MAX_DATABASES:
        blk("core", f"需要 {sc.databases} 个库 > Core 硬限制 {CORE_MAX_DATABASES}", "⭐")
    if sc.tables > CORE_MAX_TABLES:
        blk("core", f"需要 {sc.tables} 张表 > Core 硬限制 {CORE_MAX_TABLES}", "⭐")
    if sc.need_compliance:
        blk("core", "需要 SOC 2 / ISO 27001，而官方把认证列在 Enterprise 的能力清单里", "⭐")

    # --- Serverless 专属硬约束（官方 which-influxdb-3 页明列）---
    if sc.need_native_v3_api:
        blk("serverless",
            "必须用原生 v3 写 API；官方明说 Serverless「No native v3 write API——use v1 and v2 compatibility endpoints」",
            "⭐")
    if sc.need_processing_engine:
        blk("serverless", "必须用 Processing Engine；官方明说 Serverless「No Processing Engine」", "⭐")
    if sc.need_ha:
        blk("serverless", "需要高可用；Serverless 是多租户共享基础设施，官方未承诺 HA", "⭐")
    if sc.retention_days > SRV_FREE["retention_days"] and sc.databases > SRV_FREE["databases"]:
        blk("serverless",
            f"超出免费层（保留 {SRV_FREE['retention_days']} 天 / {SRV_FREE['databases']} 库）"
            f"需转付费——这不是 BLOCK，是成本项（本条仅提示，见下方成本估算）",
            "📌")

    # --- Enterprise 约束（不是 BLOCK，是许可证类型选择）---
    #    官方：At-Home 仅 2 核、仅单节点、不可商用
    if not sc.commercial and sc.ops_headcount <= 1:
        pass  # 非商用小场景可走 At-Home，下面 SKU 选择里体现

    # --- Dedicated / Clustered：容量门槛 ---
    #    官方定价页：Dedicated 与 Clustered 均为「Contact Sales / Request a POC」
    if sc.points_per_sec < 50_000 and sc.want_managed:
        blk("dedicated",
            f"写入仅 {sc.points_per_sec:,} 点/秒，官方对 Dedicated 的定位是"
            f"「high-volume production workloads」，此量级用 Serverless 更划算",
            "⚠️")

    return out


# ============================================================
# 四、打分（在未被 BLOCK 的 SKU 之间排序）
# ============================================================

@dataclass
class Rule:
    name: str
    basis: str            # ⭐ / ⚠️ / 📌
    weight: int
    fn: Callable[[Scenario, Sku], int]   # 返回 0-5


def r_cost(sc: Scenario, sku: Sku) -> int:
    """成本适配度：按量计费对小负载友好，对大负载危险。"""
    monthly_gb = sc.points_per_sec * BYTES_PER_POINT * 86_400 * sc.retention_days / 1024**3
    if sku.metered:
        # 按量：存储月费 = GB × $1.46；>1TB 后单价劣势放大
        if monthly_gb < 200:
            return 5
        if monthly_gb < 1000:
            return 4
        if monthly_gb < 5000:
            return 2
        return 1
    if sku.free_tier:
        return 5
    # 自托管商业版：人少就贵（运维成本）
    return 4 if sc.ops_headcount >= 3 else 2


def r_ops(sc: Scenario, sku: Sku) -> int:
    """
    运维负担：托管 > 自托管（当运维人力不足时权重放大）。

    ⚠️ 曾漏掉的维度：只看 ops_headcount，忽略了 want_managed。
       结果 hybrid 场景「想托管 + 只有 1 人运维」仍被推荐自托管的 Enterprise，
       而讲义正文在批评这件事 —— 嘴上说矛盾，手上照样推荐。
       修复：把「想托管但选了自托管」直接判定为高风险（1 分）。
    """
    if sku.managed:
        return 5
    if sc.want_managed:
        # 想托管却选了自托管 —— 无论有几个人，都是违背意愿的高风险
        return 1
    if sc.ops_headcount >= 3:
        return 4
    if sc.ops_headcount == 2:
        return 3
    return 1     # 1 人运维还选自托管 = 高风险


def r_capability(sc: Scenario, sku: Sku) -> int:
    """能力匹配度：需要的能力是否都有。"""
    score = 5
    if sc.need_ha and not sku.has_ha:
        score -= 3
    if sc.need_long_range and not sku.has_compactor:
        score -= 3
    if sc.need_compliance and not sku.has_certification:
        score -= 2
    if sc.need_native_v3_api and not sku.has_native_v3_write:
        score -= 3
    if sc.need_processing_engine and not sku.has_processing_engine:
        score -= 2
    return max(0, score)


def r_future(sc: Scenario, sku: Sku) -> int:
    """演进空间：换 SKU 的代价。"""
    if sku.key == "core":
        # ⭐ 官方 upgrade-to-enterprise 页：Core→Enterprise 无需搬数据，
        #    但 "Downgrading is not supported" —— 单向门
        return 4
    if sku.key == "enterprise":
        return 5
    if sku.key == "serverless":
        return 2     # 无原生 v3 API，迁移到自托管要改写入代码
    return 3


RULES: List[Rule] = [
    Rule("硬能力匹配（HA / 长程 / 合规 / v3 API）", "⭐", 5, r_capability),
    Rule("运维负担（人力越少，托管越优）",           "📌", 3, r_ops),
    Rule("成本适配（按量 vs 授权）",                 "⚠️", 2, r_cost),
    Rule("演进空间（换 SKU 的代价）",                "⭐", 2, r_future),
]


def find_conflicts(sc: Scenario) -> List[str]:
    """
    「约束冲突」检测：约束本身自相矛盾，选型救不了，只能改需求。
    与排雷的区别：排雷是「某 SKU 不满足约束」，冲突是「约束之间打架」。
    """
    out: List[str] = []
    if sc.want_managed and sc.need_ha and sc.ops_headcount <= 1:
        out.append(
            "既想全托管、又要 HA、还只有 1 人运维 —— "
            "满足前两条的只有 Dedicated（托管 + HA），但它面向大负载，成本会显著高于你的量级")
    if sc.want_managed and sc.need_native_v3_api and sc.need_processing_engine:
        out.append(
            "想托管 + 必须用原生 v3 API + 必须用处理引擎 —— "
            "Serverless 是唯一托管里便宜的，但它两个都没有；能满足的 Dedicated 又面向大负载")
    if sc.need_long_range and sc.edge:
        out.append(
            "边缘部署 + 需要长程查询 —— Core 的可查窗口只有 3 天，"
            "边缘场景通常跑 Core，二者直接冲突")
    if sc.retention_days > INFLUX_CORE_MAX_QUERY_DAYS and sc.edge:
        out.append(
            f"边缘部署 + 需查 {sc.retention_days} 天历史 —— "
            f"边缘首选的 Core 只能查 {INFLUX_CORE_MAX_QUERY_DAYS:.0f} 天")
    return out


def weights_for(sc: Scenario) -> Dict[str, int]:
    """权重随场景浮动 —— 不存在通用最优解（沿用 L17 原则）。"""
    w = {r.name: r.weight for r in RULES}
    if sc.ops_headcount == 1:
        w["运维负担（人力越少，托管越优）"] = 5      # 一个人运维，运维成本压倒一切
    if sc.points_per_sec > 100_000:
        w["成本适配（按量 vs 授权）"] = 4           # 大写入量，按量计费会失控
    if sc.edge:
        w["运维负担（人力越少，托管越优）"] = 1      # 边缘本来就得自己跑
        w["成本适配（按量 vs 授权）"] = 4
    return w


# ============================================================
# 五、跨产品提醒（层次差检查，L17 核心结论的落地）
# ============================================================

LEVEL_HINT = (
    "⚠️ 层次差检查（L17 核心结论）：InfluxDB 是**存储引擎**，不是完整监控方案。\n"
    "   若你要的是「采集 + 存储 + 告警 + 服务发现」全家桶，Prometheus 才是那个层级的答案；\n"
    "   选 InfluxDB 意味着 Telegraf 采集、Grafana 展示、处理引擎告警都要自己配。"
)

JOIN_HINT = (
    "⚠️ JOIN 提醒：InfluxDB 3 基于 DataFusion，**技术上支持 SQL JOIN**；\n"
    "   但 JOIN 维表密集的分析场景，TimescaleDB（PostgreSQL 扩展）是更自然的落点\n"
    "   —— 这是 L17 实验 A 中「业务指标分析」场景的冠军，本脚本不推翻该结论。"
)


# ============================================================
# 六、打印
# ============================================================

def hr(ch: str = "=", n: int = 78) -> str:
    return ch * n


def run_one(sc: Scenario) -> None:
    print(hr())
    print(f"场景：{sc.name}   [{sc.key}]")
    print(hr())
    print(f"  约束：保留 {sc.retention_days} 天 ｜ 写入 {sc.points_per_sec:,} 点/秒 ｜ "
          f"{sc.databases} 库 / {sc.tables} 表")
    print(f"        HA={'需要' if sc.need_ha else '不需要'} ｜ "
          f"长程查询={'需要' if sc.need_long_range else '不需要'} ｜ "
          f"合规={'需要' if sc.need_compliance else '不需要'}")
    print(f"        原生v3 API={'必须' if sc.need_native_v3_api else '非必须'} ｜ "
          f"处理引擎={'必须' if sc.need_processing_engine else '非必须'} ｜ "
          f"想托管={'是' if sc.want_managed else '否'} ｜ 运维人力 {sc.ops_headcount} 人")
    print()

    # --- 步骤 1：层次差与 JOIN 提醒 ---
    print("【步骤 1】层次差 / JOIN 前置检查")
    print("  " + LEVEL_HINT.replace("\n", "\n  "))
    if sc.join_heavy:
        print()
        print("  " + JOIN_HINT.replace("\n", "\n  "))
    print()

    # --- 步骤 1.5：约束冲突检测 ---
    conflicts = find_conflicts(sc)
    if conflicts:
        print("【步骤 1.5】⚠️ 约束冲突检测（约束本身打架，选型救不了）")
        for c in conflicts:
            print(f"  ⚠️ {c}")
        print()
        print("  → 这类冲突的唯一解法是回到需求侧改约束，而不是换一个 SKU。")
        print("    下面的排雷与打分照常给出，但请带着上面的冲突一起看。")
        print()

    # --- 步骤 2：排雷 ---
    print("【步骤 2】硬约束排雷（命中即 BLOCKED，不参与排序）")
    blockers = find_blockers(sc)
    blocked = set()
    if not blockers:
        print("  ✅ 五个 SKU 均未命中硬约束")
    for b in blockers:
        blocked.add(b.sku_key)
        tag = "🚫" if b.basis != "📌" else "💡"
        print(f"  {tag} [{b.basis}] {SKUS[b.sku_key].name}")
        print(f"        {b.reason}")
    # 📌 提示类不算真 BLOCK
    blocked = {k for k in blocked
               if any(b.sku_key == k and b.basis != "📌" for b in blockers)}
    print()
    print(f"  → 进入打分的 SKU：{len([k for k in SKUS if k not in blocked])} / {len(SKUS)}")
    print()

    # --- 步骤 3：打分 ---
    print("【步骤 3】加权打分（权重由场景决定）")
    w = weights_for(sc)
    print(f"  权重：{w}")
    print()
    results: List[Tuple[str, float, List[Tuple[str, int, int]]]] = []
    for key, sku in SKUS.items():
        if key in blocked:
            continue
        detail: List[Tuple[str, int, int]] = []
        total = 0
        for rule in RULES:
            raw = rule.fn(sc, sku)
            total += raw * w[rule.name]
            detail.append((rule.name, raw, w[rule.name]))
        results.append((key, total, detail))

    max_total = max((t for _, t, _ in results), default=1)
    results.sort(key=lambda x: -x[1])
    for key, total, detail in results:
        pct = total / max_total * 100 if max_total else 0
        print(f"  {SKUS[key].name:<32} {total:>6.1f} 分  ({pct:>5.1f}%)")
        for name, raw, ww in detail:
            print(f"        {name:<34} {raw}/5 × {ww}")
    print()

    if not results:
        print("  ⚠️ 所有 SKU 都被 BLOCK —— 说明该场景的约束不成立，需回到需求侧重新定义")
        print()
        return

    # --- 步骤 4：结论 ---
    win_key, win_total, _ = results[0]
    win = SKUS[win_key]
    print(f"【步骤 4】结论：{win.name}")
    print(f"  {win.note}")
    print()

    # --- 步骤 5：许可证 / 规格建议（仅 Enterprise / Core）---
    if win_key == "enterprise":
        print("  ▶ 许可证选择（官方 enterprise/admin/license 页）：")
        if not sc.commercial and not sc.need_ha and sc.ops_headcount <= 1:
            print("     At-Home   —— 免费、2 核、单节点、永不过期；⚠️ 官方明说不可商用")
        elif sc.need_ha or sc.commercial:
            print("     Trial     —— 30 天、256 核、全功能；⚠️ 官方明说不可商用（只能评估）")
            print("     Commercial—— 商用唯一选项；按 CPU 核批量 8/16/32/64/128 购买")
            cpu = pick_cpu_batch(sc)
            print(f"     📌 核数推算：{cpu} 核（按 {sc.points_per_sec:,} 点/秒推算，见实验 B）")
    if win_key == "core":
        print("  ▶ 部署提醒：")
        print(f"     可查窗口 {INFLUX_CORE_MAX_QUERY_DAYS:.0f} 天；"
              f"硬限制 {CORE_MAX_DATABASES} 库 / {CORE_MAX_TABLES} 表 / {CORE_MAX_COLUMNS} 列")
        print("     ⭐ 官方：Core→Enterprise 无需搬数据，但 Downgrading is not supported（单向门）")
    if win_key == "serverless":
        print("  ▶ 计费提醒（官方定价页四个单价）：")
        print(f"     写入 $0.0025/MB ｜ 查询 $0.012/100 次 ｜ "
              f"存储 $0.002/GB-hour（≈ ${SRV_STORAGE_PER_GB_MONTH:.2f}/GB/月）｜ 出流量 $0.09/GB")
        print(f"     免费层上限：写入 {SRV_FREE['write_mb_per_5min']}MB/5min ｜ "
              f"查询 {SRV_FREE['query_mb_per_5min']}MB/5min ｜ "
              f"保留 {SRV_FREE['retention_days']} 天 ｜ {SRV_FREE['databases']} 个库")
    print()


def pick_cpu_batch(sc: Scenario) -> int:
    """
    📌 核数推算（本课推导，非官方公式）：
    官方性能调优页给的锚点是「32 核系统 → 写密集 >100k 点/秒」。
    据此线性外推到本场景写入量，再向上取整到官方售卖批次。
    ⚠️ 这是粗略估算，真实容量必须用自家数据压测。
    """
    anchor_cores = 32
    anchor_pps = 100_000
    raw = sc.points_per_sec / anchor_pps * anchor_cores
    for batch in ENT_CPU_BATCHES:
        if raw <= batch:
            return batch
    return ENT_CPU_BATCHES[-1]


def main() -> None:
    print(hr("#"))
    print("L19 · 实验 A：选型决策树引擎")
    print("「哪个更好」→「在我的约束下，哪个总成本最低」")
    print(hr("#"))
    print()
    print("本脚本常量的依据分布：")
    print(f"  ⭐ 官方一手：Core 可查窗口 {INFLUX_CORE_MAX_QUERY_DAYS:.0f} 天、"
          f"Core 硬限制 {CORE_MAX_DATABASES}/{CORE_MAX_TABLES}/{CORE_MAX_COLUMNS}、"
          f"Serverless 四个单价")
    print(f"  ⭐ 官方一手：三种许可证规格、CPU 售卖批次 {ENT_CPU_BATCHES}")
    print(f"  ⚠️ 推算：Enterprise 容量 {ENT_MIN_DATABASES}+ 库 / {ENT_MIN_TABLES}+ 表（官方博客口径）")
    print(f"  📌 本课推导：每点字节数 {BYTES_PER_POINT:.2f} B（由 L13 官方锚点反推）、"
          f"存储月费 ${SRV_STORAGE_PER_GB_MONTH:.2f}/GB")
    print()

    for sc in SCENARIOS:
        run_one(sc)

    print(hr("#"))
    print("收束：四个场景的四个结论")
    print(hr("#"))
    print()
    print("  1. 没有任何一个 SKU 通吃四个场景 —— 和 L17「没有一款赢下全部场景」是同一条规律，")
    print("     只是这次发生在**同一个产品的不同 SKU 之间**。")
    print("  2. 「我们选了 InfluxDB」这句话本身没有信息量 —— 五个 SKU 的硬约束差异极大，")
    print("     Core 的 3 天窗口和 5 库限制，能把生产场景直接挡在门外。")
    print("  3. 排雷命中率最高的是 Core：四个场景里三个被 BLOCK。这不是 Core 不好，")
    print("     是它的官方定位就是「non-production, edge, or single-node」。")
    print("  4. 四个场景里有两个触发了**约束冲突**（hybrid / IoT）—— 既想托管又要用")
    print("     原生 v3 API。这类冲突换任何 SKU 都解不了，只能回到需求侧改约束。")
    print("     ⚠️ 打分器在这种场景下仍会输出一个冠军，但那个冠军是「最不坏」，不是「好」。")
    print()


if __name__ == "__main__":
    main()
