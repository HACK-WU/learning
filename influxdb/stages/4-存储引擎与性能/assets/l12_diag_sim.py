# -*- coding: utf-8 -*-
"""慢查询诊断决策树模拟器 —— 纯标准库，可直接运行
对照 L12 知识点 3：慢查询诊断
把「按症状倒查」的诊断路径写成可执行的形式：
给定观测到的症状组合，输出该看什么、最可能的原因是什么。
"""
import time
import random

random.seed(20260901)

FILES_PER_DAY = 144   # gen1-duration=10m -> 144 个文件/天
LIMIT = 432           # query-file-limit 默认


def diagnose(files_scanned, has_time_filter, columns_selected, total_columns,
             has_lvc, is_last_value, order_by_big, plan_ms, exec_ms):
    """给定一组观测值，返回诊断结论列表（按优先级排序）"""
    verdicts = []

    # 第一优先级：是不是直接报错
    if files_scanned > LIMIT:
        verdicts.append((
            "P0", "文件数超限",
            "扫描 {} 个文件 > 限制 {}".format(files_scanned, LIMIT),
            "这不是慢，是拒绝执行。收窄时间范围，或接受官方列的四条副作用后调 --query-file-limit"))

    # 第二优先级：有没有时间过滤（分区裁剪的唯一输入）
    if not has_time_filter:
        verdicts.append((
            "P0", "缺时间谓词",
            "WHERE 里没有 time 条件",
            "分区裁剪完全失效，等于全表扫描。这是 Core 上最高频的慢查询原因"))

    # 第三优先级：投影下推（列数）
    col_ratio = columns_selected / total_columns
    if total_columns >= 1000 and col_ratio > 0.5:
        verdicts.append((
            "P1", "宽表 SELECT *",
            "选了 {}/{} 列（{:.0f}%）".format(columns_selected, total_columns, col_ratio * 100),
            "官方：10 列的表 SELECT * 差距很小，1000+ 列才会明显变慢"))
    elif total_columns < 20 and col_ratio > 0.5:
        verdicts.append((
            "P3", "列数不是瓶颈",
            "只选了 {}/{} 列，但表本来就窄".format(columns_selected, total_columns),
            "列存已经替你省了，别在 SELECT 上花时间，去看文件数和 ORDER BY"))

    # 第四优先级：last-value 类查询有没有走 LVC
    if is_last_value and not has_lvc:
        verdicts.append((
            "P1", "last-value 没走缓存",
            "是「查最新值」类查询，但没配 LVC",
            "创建 last_cache 并用 SQL 查（InfluxQL 不支持 last_cache()），否则每次都要扫文件"))

    # 第五优先级：ORDER BY 大排序
    if order_by_big:
        verdicts.append((
            "P2", "大排序",
            "ORDER BY 作用于大量行",
            "官方列为「不受你控制的瓶颈」之一：对已排序的数据再排序。考虑在聚合后排序而非原始行"))

    # 第六优先级：计划时间 vs 执行时间
    if plan_ms > exec_ms and plan_ms > 100:
        verdicts.append((
            "P2", "规划耗时 > 执行耗时",
            "plan {}ms vs exec {}ms".format(plan_ms, exec_ms),
            "典型症状是文件数太多导致 planning 变慢——根因还是文件数，不是 SQL 写得差"))

    if not verdicts:
        verdicts.append((
            "OK", "未发现明显瓶颈",
            "文件数、时间谓词、列数、排序都正常",
            "走 EXPLAIN ANALYZE 看各 Exec 节点的实际耗时，或直接查 system.queries"))

    return verdicts


print("=" * 70)
print("实验 B：慢查询诊断决策树模拟器")
print("=" * 70)
print("用法：给定观测到的症状，输出「该看什么 + 最可能的原因 + 动作」")
print("文件数换算：gen1-duration=10m -> 每天 {} 个文件；query-file-limit={}\n".format(
    FILES_PER_DAY, LIMIT))

cases = [
    {
        "name": "场景 1：运营跑月度报表，查 30 天",
        "files_scanned": 30 * FILES_PER_DAY,
        "has_time_filter": True,
        "columns_selected": 3,
        "total_columns": 12,
        "has_lvc": False,
        "is_last_value": False,
        "order_by_big": True,
        "plan_ms": 420,
        "exec_ms": 3800,
    },
    {
        "name": "场景 2：大屏每 5 秒刷新 5 万个信号的最新值（未配 LVC）",
        "files_scanned": 6,
        "has_time_filter": True,
        "columns_selected": 2,
        "total_columns": 8,
        "has_lvc": False,
        "is_last_value": True,
        "order_by_big": False,
        "plan_ms": 15,
        "exec_ms": 220,
    },
    {
        "name": "场景 3：宽表（1200 列）上 SELECT *",
        "files_scanned": 12,
        "has_time_filter": True,
        "columns_selected": 1200,
        "total_columns": 1200,
        "has_lvc": False,
        "is_last_value": False,
        "order_by_big": False,
        "plan_ms": 60,
        "exec_ms": 900,
    },
    {
        "name": "场景 4：BI 工具拖出来的查询，WHERE 里没有时间条件",
        "files_scanned": 90 * FILES_PER_DAY,
        "has_time_filter": False,
        "columns_selected": 5,
        "total_columns": 12,
        "has_lvc": False,
        "is_last_value": False,
        "order_by_big": False,
        "plan_ms": 900,
        "exec_ms": 250,
    },
    {
        "name": "场景 5：查最近 1 小时的健康查询（对照组）",
        "files_scanned": 6,
        "has_time_filter": True,
        "columns_selected": 3,
        "total_columns": 12,
        "has_lvc": False,
        "is_last_value": False,
        "order_by_big": False,
        "plan_ms": 8,
        "exec_ms": 45,
    },
]

for case in cases:
    print("-" * 70)
    print(case["name"])
    print("-" * 70)
    vs = diagnose(
        case["files_scanned"], case["has_time_filter"],
        case["columns_selected"], case["total_columns"],
        case["has_lvc"], case["is_last_value"], case["order_by_big"],
        case["plan_ms"], case["exec_ms"])
    for level, title, evidence, action in vs:
        print("  [{}] {}".format(level, title))
        print("       证据：{}".format(evidence))
        print("       动作：{}".format(action))
    print()

print("=" * 70)
print("诊断顺序总结（先看什么，后看什么）")
print("=" * 70)
order = [
    ("第 1 步", "有没有报错？", "报错里带 exceeding the file limit -> 文件数超限，收窄时间范围"),
    ("第 2 步", "WHERE 里有没有 time？", "没有 -> 分区裁剪全失效，这是最高频的原因"),
    ("第 3 步", "file_groups 有几个文件？", "接近 432 -> 已在悬崖边；几十个以内正常"),
    ("第 4 步", "projection 有几列？", "1000+ 列表上 SELECT * 才值得改；十几列不用管"),
    ("第 5 步", "是不是 last-value 类查询？", "是且没配 LVC -> 建 last_cache，注意只能用 SQL 查"),
    ("第 6 步", "plan 时间 vs exec 时间", "plan 更大 -> 文件数太多；exec 更大 -> 看 ORDER BY 与聚合"),
    ("第 7 步", "system.queries 找历史", "按 end2end_duration 倒序，找出最慢的一批再逐个 EXPLAIN ANALYZE"),
]
for step, question, hint in order:
    print("{}  {}".format(step, question))
    print("      {}".format(hint))
print("=" * 70)
