"""诊断：{__name__=~".+"} 为什么只命中 0 条？

讲义步骤 8 预期命中 20832 条（0.36 秒），复验时命中 0 条（0.12 秒）。
必须查清，否则读者照抄会得到与讲义相反的结果。
"""
import json
import time

from l6lib import _wget, app_get, query, now

print("== 1. 当前库里到底有多少序列 ==")
d = json.loads(_wget("/api/v1/status/tsdb"))["data"]
print("   headStats.numSeries =", d["headStats"]["numSeries"])
print("   seriesCountByMetricName 前 5:")
for s in d.get("seriesCountByMetricName", [])[:5]:
    print(f"      {s['name']}: {s['value']}")

print()
print("== 2. 多种写法对比命中数 ==")
cases = [
    '{__name__=~".+"}',
    '{__name__=~".*"}',
    '{__name__!=""}',
    'l6_card_metric',
    'up',
    'l6_up',
]
for q in cases:
    r = query(q)
    n = len(r) if r else 0
    print(f"   {q:<22} 命中 {n} 条")

print()
print("== 3. 数据是否还在（前面的步骤是否清空了） ==")
print("   app health:", app_get("/health"))
r = query("l6_concurrency")
print("   l6_concurrency:", r[0]["value"][1] if r else "无")

print()
print('== 4. 灌数据后重测 {__name__=~".+"} ==')
print("   生成 20000 条序列并等待...")
print(app_get("/cardinality?n=20000"))
time.sleep(20)
for q in ['{__name__=~".+"}', 'l6_card_metric']:
    r = query(q)
    n = len(r) if r else 0
    print(f"   {q:<22} 命中 {n} 条")

print()
print("== 5. 带时间参数的历史查询 ==")
t = now() - 30
for q in ['{__name__=~".+"}', 'l6_card_metric']:
    r = query(q, t=t)
    n = len(r) if r else 0
    print(f"   {q:<22} @30s前 命中 {n} 条")
