# -*- coding: utf-8 -*-
"""
❌ 反例：单文件脚本版体检器（bad_example.py）

**它能跑通**，甚至初看更简洁 —— 只有 60 行，一个文件搞定所有检查。
问题在于：它把五个阶段的检查全部硬编码进一个函数，每加一条规则就要改这个函数。

对应 反例对照.md 的逐条对比。**不要照着这个写**，它是用来对照的反面教材。
"""

QUERY_FILE_LIMIT = 432
FILES_PER_DAY = 144


def check(name, pps, days, tags, fields, want_managed, need_v3,
          need_pe, need_ha, telegraf_urls, db_tag_card, org, panels, refresh):
    problems = []

    # 硬限制（写死在这里，别的模块拿不到）
    if len(tags) + len(fields) + 1 > 500:
        problems.append("列数超限")

    # 基数
    series = 1
    for v in tags.values():
        series *= v
    if pps / series < 0.01:
        problems.append("点密度太低")

    # ⚠️ 致命：把 432 无条件套用到所有形态，不管选的是哪个 SKU
    files = FILES_PER_DAY * days
    if files > QUERY_FILE_LIMIT:
        problems.append(f"文件数 {files:.0f} 超限")

    # 降采样：只按默认 10 分钟算，从不读用户配置的调度周期
    if days * 24 * 6 > QUERY_FILE_LIMIT:
        problems.append("降采样层超限")

    # 保留期：只检查了一个坑
    if days <= 0:
        problems.append("保留期必须为正")

    # Telegraf：只看了 URL 数量，语义理解成负载均衡
    if len(telegraf_urls) > 1:
        problems.append("多 URL 有负载均衡风险")
    if db_tag_card > 5:
        problems.append("database_tag 库数超限")
    if org:
        problems.append("organization 非空")

    # SKU 排雷：只排了一个，而且没区分「不满足」与「约束打架」
    if want_managed and need_v3 and need_pe:
        problems.append("Serverless 不满足")

    # 成本：只算机器钱，人力按 0 处理
    cost = 240
    if panels and refresh:
        cost += panels * (60 / refresh) * 60 * 730 / 100 * 0.012

    return problems, cost


if __name__ == "__main__":
    p, c = check(
        name="IoT", pps=50_000, days=90,
        tags={"device_id": 20_000, "site": 20, "sensor": 5},
        fields=["temperature", "humidity", "voltage"],
        want_managed=True, need_v3=False, need_pe=False, need_ha=False,
        telegraf_urls=["http://a:8181", "http://b:8181"],
        db_tag_card=20, org="my-org", panels=12, refresh=30,
    )
    print("问题：", p)
    print("月成本：$%.2f" % c)
