# -*- coding: utf-8 -*-
"""部署形态选型决策树模拟器 —— 纯标准库，可直接运行
对照 L13 知识点 1：Core / Enterprise / Cloud 选型

给定一组业务需求，输出推荐形态、理由与「如果不听推荐会怎样」。
判定规则全部来自官方文档原文（which-influxdb-3 页 / Enterprise 架构页 /
Core config-options 页 / 官方定价页），不含推测。
"""
import time
import random

random.seed(20260901)

FILES_PER_DAY = 144     # gen1-duration=10m -> 144 个文件/天
LIMIT = 432             # query-file-limit 默认


def recommend(need_ha, need_historical, query_days, need_v3_api, need_pe,
              want_managed, is_aws_native, daily_gb, need_compliance):
    """给定业务需求，返回 (推荐形态, 判据列表, 风险提示)"""
    reasons = []
    risks = []

    # 判据 1：查询时间范围 —— 这是 Core 与 Enterprise 的分水岭
    files = FILES_PER_DAY * query_days
    if files > LIMIT:
        reasons.append((
            "查询范围 {} 天 = {:,} 个文件 > Core 上限 {}".format(query_days, files, LIMIT),
            "**若选 Core 会直接报错**（不是变慢，L11 已核实）" +
            " → 自托管须上 Enterprise（compactor）；托管形态由服务端处理，不受此限"))

    # 判据 2：高可用
    if need_ha:
        reasons.append((
            "需要高可用 / 多节点",
            "Core 是**单节点**（官方原文 single-node）→ 必须 Enterprise 或托管形态"))

    # 判据 3：合规认证
    if need_compliance:
        reasons.append((
            "需要 ISO 27001 / SOC 2 / SSO",
            "Enterprise 原生支持 SAML/SSO；Cloud Dedicated 为 add-on；Core 无"))

    # 注意：原生 v3 API / 处理引擎只用于**排除 Cloud Serverless**（托管分支），
    # 不构成 Core → Enterprise 的升级理由。Core 本身就带原生 v3 API 与处理引擎，
    # 因此该判据不进 reasons，而在下面的托管分支里单独判断。

    # 判据 4：是否要托管
    if want_managed:
        if is_aws_native:
            return ("Amazon Timestream for InfluxDB", reasons, [
                "AWS 原生托管，走 AWS 账单，可抵扣 EDP 承诺",
                "⚠️ 注意 SKU：有 InfluxDB 2.x 与 InfluxDB 3 Core / Enterprise 多种引擎可选，选错引擎等于选错代际"])
        if daily_gb <= 50 and not need_v3_api and not need_pe:
            return ("InfluxDB Cloud Serverless", reasons, [
                "⚠️ 没有原生 v3 写入 API（只能用 v1/v2 兼容端点）",
                "⚠️ 没有处理引擎",
                "⚠️ 查询按次计费（$0.012/100 次），高频刷新的大屏会推高账单",
                "⚠️ 免费层仅 30 天保留"])
        return ("InfluxDB Cloud Dedicated", reasons, [
            "单租户独占、性能隔离、支持自定义分区",
            "⚠️ 价格按配置的总 CPU/RAM 与存储量而定，需询价"])

    # 自托管分支
    if not reasons:
        return ("InfluxDB 3 Core", reasons, [
            "✅ 免费开源、单节点足够",
            "✅ Core 自带原生 v3 写入 API 与处理引擎（与 Enterprise 同源）",
            "⚠️ 升级到 3.10+ 前必须备份 catalog（迁移单向不可逆）",
            "⚠️ 无高可用、无 compactor，查询范围受 432 文件限制（≈ 3 天）"])

    # 托管形态下，若需要原生 v3 API / 处理引擎，显式追加「排除 Serverless」的判据
    if want_managed and (need_v3_api or need_pe):
        reasons.append((
            "需要原生 v3 写入 API 或处理引擎",
            "官方原文：Cloud Serverless **没有**原生 v3 写入 API、**没有**处理引擎 → 排除 Serverless"))

    return ("InfluxDB 3 Enterprise", reasons, [
        "✅ 满足上述全部硬性需求",
        "⚠️ 需要许可证（Trial / Home / Commercial）",
        "⚠️ 同样必须先备份 catalog 再升级 3.10+"])


print("=" * 76)
print("实验 B：部署形态选型决策树模拟器")
print("=" * 76)
print("用法：给定业务需求，输出推荐形态 + 判据 + 「不听推荐会怎样」")
print("判定规则全部取自官方文档原文，不含推测\n")

cases = [
    {
        "name": "场景 1：边缘网关，单机采集 200 台设备，只看最近 24 小时",
        "need_ha": False, "need_historical": False, "query_days": 1,
        "need_v3_api": True, "need_pe": False, "want_managed": False,
        "is_aws_native": False, "daily_gb": 2, "need_compliance": False,
    },
    {
        "name": "场景 2：生产监控平台，要查近 90 天趋势，需高可用",
        "need_ha": True, "need_historical": True, "query_days": 90,
        "need_v3_api": True, "need_pe": True, "want_managed": False,
        "is_aws_native": False, "daily_gb": 200, "need_compliance": True,
    },
    {
        "name": "场景 3：小团队做 PoC，日写入 5GB，想零运维，用 v2 客户端",
        "need_ha": False, "need_historical": False, "query_days": 7,
        "need_v3_api": False, "need_pe": False, "want_managed": True,
        "is_aws_native": False, "daily_gb": 5, "need_compliance": False,
    },
    {
        "name": "场景 4：AWS 原生团队，想把账单并入 AWS 合同",
        "need_ha": True, "need_historical": True, "query_days": 30,
        "need_v3_api": True, "need_pe": False, "want_managed": True,
        "is_aws_native": True, "daily_gb": 100, "need_compliance": True,
    },
    {
        "name": "场景 5：开发机本地跑，学 v3 原生 API，写处理引擎插件",
        "need_ha": False, "need_historical": False, "query_days": 1,
        "need_v3_api": True, "need_pe": True, "want_managed": False,
        "is_aws_native": False, "daily_gb": 1, "need_compliance": False,
    },
    {
        "name": "场景 6：中型业务，日写入 80GB，要托管但要原生 v3 API",
        "need_ha": True, "need_historical": True, "query_days": 60,
        "need_v3_api": True, "need_pe": True, "want_managed": True,
        "is_aws_native": False, "daily_gb": 80, "need_compliance": True,
    },
]

for case in cases:
    print("-" * 76)
    print(case["name"])
    print("-" * 76)
    pick, reasons, risks = recommend(
        case["need_ha"], case["need_historical"], case["query_days"],
        case["need_v3_api"], case["need_pe"], case["want_managed"],
        case["is_aws_native"], case["daily_gb"], case["need_compliance"])
    print("  ➜ 推荐形态：{}\n".format(pick))
    if reasons:
        print("  判定依据：")
        for evidence, conclusion in reasons:
            print("    · {}".format(evidence))
            print("      → {}".format(conclusion))
    else:
        print("  判定依据：未触发任何硬性排除条件，默认最简形态即可满足\n")
    print("  风险与注意：")
    for r in risks:
        print("    · {}".format(r))
    print()

print("=" * 76)
print("一句话选型口诀")
print("=" * 76)
tips = [
    ("先问「要查多久」", "超过 3 天（432 文件）就别考虑 Core —— 它是报错，不是慢"),
    ("再问「要几个九」", "要高可用 / 多节点 / SSO / 合规 → Enterprise 或托管形态"),
    ("最后问「谁运维」", "想零运维 → Cloud；但 Serverless 没有原生 v3 API 与处理引擎"),
    ("AWS 原生看这里", "Amazon Timestream for InfluxDB 走 AWS 账单，**注意选引擎 SKU**"),
    ("无论选哪个", "升级 3.10+ 前**必须备份 catalog**，迁移单向不可逆"),
]
for q, a in tips:
    print("  · {}".format(q))
    print("      {}".format(a))
print("=" * 76)
