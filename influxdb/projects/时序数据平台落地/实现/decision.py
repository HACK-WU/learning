# -*- coding: utf-8 -*-
"""
decision.py —— 阶段 6 选品（L17 横向对比 / L18 迁移 / L19 选型决策）

📌 回指：L17《横向对比：五款候选》、L18《迁移指南》、L19《场景演练与选型决策》

本模块回答三个问题：
  1. 约束之间打不打架（L19 新增的冲突检测 —— 这类问题换 SKU 也解不了）
  2. 五个 SKU 里哪些被硬约束排除（先排雷，再打分）
  3. 从 1.x/2.x 迁过来时，哪些差异会静默出错（L18 的 reverse / drift 分类）
"""

from config import Finding, Workload


# ===== L17：层次差 —— 先判断要不要跟 Prometheus 比 ==================

def check_layering(w: Workload) -> list:
    """⭐ L17 核心：InfluxDB 是存储引擎，Prometheus 是完整监控方案。"""
    out = []
    if w.name.startswith("K8s"):
        out.append(Finding(
            "P1", "阶段 6 · L17",
            "拿 InfluxDB 跟 Prometheus 直接比是不公平对照",
            "⭐ InfluxDB 是存储引擎（发动机），Prometheus 是采集 + 存储 + 告警 + 服务发现的完整方案（整车）。"
            "InfluxDB 要凑成完整方案还缺 Telegraf（采集）、Grafana（展示）、处理引擎（告警）。",
            "要比就比「InfluxDB + Telegraf + Grafana」vs「Prometheus」，或比存储层对存储层",
        ))

    out.append(Finding(
        "INFO", "阶段 6 · L17",
        "推模式 vs 拉模式：官方自己说这不是重点",
        '⭐ Prometheus 官方 FAQ 原文：pulling is "slightly better than pushing, '
        'but it should not be considered a major point"。',
        "选型时别把它当主要判据",
    ))
    return out


# ===== L19：约束冲突检测 =============================================

def find_conflicts(w: Workload) -> list:
    """⭐ L19 P1-1：区分「某 SKU 不满足约束」与「约束之间打架」。"""
    out = []

    if w.want_managed and w.need_ha and w.ops_headcount <= 1:
        out.append(Finding(
            "P0", "阶段 6 · L19",
            "约束冲突：既想全托管、又要 HA、还只有 1 人运维",
            "想托管 → Serverless / Dedicated；要 HA → Dedicated（Serverless 的多租户形态不承诺单租户 HA）；"
            "而 Dedicated 面向大负载，1 个人扛不动对接与容量规划工作。",
            "这不是选型能解的问题 —— 回需求侧：要么加人，要么放弃 HA，要么接受自托管",
        ))

    if w.want_managed and w.need_native_v3_api and w.need_processing_engine:
        out.append(Finding(
            "P0", "阶段 6 · L19",
            "约束冲突：想托管 + 必须用原生 v3 API + 必须用处理引擎",
            "⭐ Serverless 官方明说：'No native v3 write API'、'No Processing Engine'。"
            "而 Core 有这两项但不是托管。想三者兼得只能上 Dedicated（成本大幅上升）。",
            "回需求侧确认：这三个约束哪个能让步。多数情况是处理引擎可改用外部服务",
        ))

    if w.edge and w.query_window_days > 3:
        out.append(Finding(
            "P0", "阶段 6 · L19",
            f"约束冲突：边缘部署 + 需要 {w.query_window_days} 天长程查询",
            "⭐ 边缘部署的默认答案是 Core，而 Core 只能查 3 天（432 文件 × 10min）。",
            "要么把长程查询放回中心侧（边缘只留短窗口），要么边缘也上有 compactor 的形态",
        ))

    if w.need_join:
        out.append(Finding(
            "P0", "阶段 6 · L17",
            "需要 JOIN —— 这是 InfluxDB 的短板，不是配置项",
            "⭐ InfluxDB 3 的 SQL 基于 DataFusion，JOIN 能力远弱于 PostgreSQL 生态。"
            "同类需求下 TimescaleDB（PostgreSQL 扩展）更对口。",
            "认真考虑 TimescaleDB；若 JOIN 只在离线分析侧用，可让 InfluxDB 只管时序、JOIN 交给数仓",
        ))
    return out


# ===== L19：SKU 排雷（先排雷，再打分）===============================

SKU_RULES = [
    # (SKU, 排除条件, 触发时的问题标题, 细节, 建议)
    ("core", lambda w: w.need_ha,
     "Core 不满足 HA", "⭐ Core 是单节点形态，官方定位为 edge / non-critical。",
     "要秒级切换必须 Enterprise"),
    ("core", lambda w: w.query_window_days > 3,
     "Core 不满足长程查询", "⭐ 432 文件 × 10min = 3 天，超限直接报错。",
     "配降采样层，或换有 compactor 的 SKU"),
    ("serverless", lambda w: w.need_native_v3_api,
     "Serverless 没有原生 v3 写 API",
     "⭐ 官方原话 'No native v3 write API—use v1 and v2 compatibility endpoints'。",
     "改用 v1/v2 兼容端点，或换 SKU"),
    ("serverless", lambda w: w.need_processing_engine,
     "Serverless 没有处理引擎",
     "⭐ 官方原话 'No Processing Engine'。告警与实时处理得放到外部。",
     "把处理引擎的逻辑外移到独立服务，或换 SKU"),
    ("clustered", lambda w: w.want_managed,
     "Clustered 是自托管形态",
     "⭐ Clustered 跑在自建 Kubernetes 上，不是托管服务。",
     "想托管就选 Serverless / Dedicated"),
    ("dedicated", lambda w: w.pps < 50_000,
     "Dedicated 面向大负载，小负载不划算",
     "⭐ Dedicated 是 Managed single-tenant，起步成本高。",
     "负载涨上来再迁；当前用 Serverless 或自托管更经济"),
]


ALL_SKUS = ("core", "enterprise", "serverless", "dedicated", "clustered")


def surviving_skus(w: Workload) -> list:
    """📌 排雷结果：返回未被硬约束排除的 SKU 列表，供下游模块做约束归属判断。

    这是本项目对「约束归属」原则的落实 —— Core 已被排除时，
    engine / ops 就不该再报 Core 专属的 432 约束（否则跟本模块的结论打架）。
    """
    blocked = {sku for sku, rule, *_ in SKU_RULES if rule(w)}
    return [s for s in ALL_SKUS if s not in blocked]


def check_skus(w: Workload) -> list:
    """先排雷再打分 —— 被排除的 SKU 不参与后续打分。"""
    out = []
    blocked = []
    for sku, rule, title, detail, action in SKU_RULES:
        if rule(w):
            blocked.append(sku)
            out.append(Finding(
                "P0", "阶段 6 · L19", f"【{sku}】被排除：{title}", detail, action,
            ))

    survivors = surviving_skus(w)
    out.append(Finding(
        "INFO", "阶段 6 · L19",
        f"排雷结果：{' / '.join(survivors) if survivors else '无'}",
        f"五个 SKU 中 {len(blocked)} 个被硬约束排除（去重后：{sorted(set(blocked))}）。"
        "📌 关键：被排除不是「分数低」，是「不满足」—— 打分器给它们多少分都没意义。",
        "只在幸存者里做成本与运维比较（见 tco.py）；若为空，说明约束本身有问题，回需求侧",
    ))

    out.append(Finding(
        "P1", "阶段 6 · L19",
        "注意：Serverless 不是 Core 的托管版",
        "⭐ Serverless 缺原生 v3 API 与处理引擎，而 Core 有这两项；"
        "反过来 Core 没有 compactor，Serverless 有。两者是交叉关系，不是包含关系。",
        "别用「先上 Core 以后平滑迁 Serverless」的思路做规划 —— 迁移要改代码",
    ))
    return out


# ===== L18：迁移差异（reverse / drift 分类）=========================

# (类型, 名称, 详情, 建议动作, 命中判断函数)
# 📌 每条陷阱都带一个"本场景是否命中"的判断 —— 无差别地把 4 条全列成 P0
#    等于告诉读者"什么都危险"，反而淹没了真正命中的那条。
MIGRATION_TRAPS = [
    ("reverse", "保留期 0d",
     "1.x/2.x 的 0d = 永久保留，3.x 的 0d = 立刻全删",
     "建库后立刻 SHOW DATABASES 确认",
     lambda w: str(w.retention_period).strip().rstrip("hdw").rstrip("0123456789.") == ""
     and str(w.retention_period).strip() in ("0", "0d", "0h", "0w", "0mo", "0y")),
    ("drift", "保留期单位 mo / y",
     "mo = 30 天、y = 365 天，非日历单位，3mo 比三个自然月少 1.3 天",
     "合规场景按天写",
     lambda w: str(w.retention_period).strip().endswith(("mo", "y"))),
    ("reverse", "默认精度",
     "v1 端点默认纳秒、v3 默认 auto —— 换端点不改代码等于换了时间解释方式",
     "迁移后逐表核对时间戳量级",
     lambda w: w.source_version in ("1.x", "2.x")),
    ("drift", "术语映射",
     "bucket = database、measurement = table（官方用词 is synonymous with）",
     "改代码前先做术语对照表",
     lambda w: w.source_version == "2.x"),
]


def check_migration(w: Workload) -> list:
    """⭐ L18：静默项要按「失败时有没有声音」排，而不是按概率排。

    📌 每条陷阱会标出**本场景是否命中**：命中的 reverse 判 P0、命中的 drift 判 P1；
       未命中的降为 INFO 并说明"什么情况下会命中" —— 保留它的教学价值，
       但不让它淹没真正需要处理的问题。
    """
    out = []
    if w.source_version == "none":
        out.append(Finding(
            "INFO", "阶段 6 · L18", "无历史版本数据，跳过迁移检查", "", "",
        ))
        return out

    hits = {"reverse": 0, "drift": 0}
    for kind, name, detail, action, hit_fn in MIGRATION_TRAPS:
        hit = hit_fn(w)
        if hit:
            hits[kind] += 1
            level = "P0" if kind == "reverse" else "P1"
            mark = "⚠️ 本场景命中"
        else:
            level = "INFO"
            mark = "本场景未命中（保留作检查项）"
        label = "方向反了（灾难级）" if kind == "reverse" else "幅度偏了（合规级）"
        out.append(Finding(
            level, "阶段 6 · L18",
            f"[{kind}] {name} —— {label} · {mark}", detail, action,
        ))

    if hits["reverse"]:
        out.append(Finding(
            "P0", "阶段 6 · L18",
            f"从 {w.source_version} 迁移：{hits['reverse']} 条 reverse 型差异在本场景命中，必须逐条人工核对",
            "⭐ L18 的方法论：迁移风险按「失败时有没有声音」排序，不按「会不会失败」排序。"
            "报错型最坏是延期，reverse 型最坏是丢数据且无人知晓。",
            "把 reverse 型做成上线前的强制检查项，不接受「应该没问题」",
        ))
    else:
        out.append(Finding(
            "INFO", "阶段 6 · L18",
            f"从 {w.source_version} 迁移：本场景未命中 reverse 型差异",
            f"已核对 {len(MIGRATION_TRAPS)} 条已知陷阱，其中 {hits['drift']} 条 drift 型命中（见上方 P1）。"
            "⚠️ 这不代表没有其它 reverse 型差异 —— 本表只覆盖课程已核实的条目。",
            "上线前仍按 L18 的七阶段清单走一遍",
        ))

    out.append(Finding(
        "P1", "阶段 6 · L18",
        "双写窗口可以算出来，别凭感觉定",
        "⭐ 下限 = 对账周期（1-3 天），上限 = 可查窗口（Core 仅 3 天）"
        "→ Core 上双写窗口实际只有 1-3 天。写太久，最早的数据反而查不到，双写失去对照意义。",
        "对账脚本必须提前写好，不能边双写边开发",
    ))
    return out


def run(w: Workload) -> list:
    return (check_layering(w) + find_conflicts(w)
            + check_skus(w) + check_migration(w))
