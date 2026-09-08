import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"


def query(q):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": q})
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]


def group_label(m):
    """rule_group 标签形如 '/etc/prometheus/rules.yml;l4-A-slow'，取分号后部分。"""
    g = m.get("rule_group", "?")
    return g.split(";")[-1] if ";" in g else g


def short_rule(m):
    r = m.get("rule", "?")
    return r.split(";")[-1] if ";" in r else r


print("### 1) 规则组求值耗时（秒） ###")
res = query("prometheus_rule_group_last_duration_seconds")
rows = sorted(((group_label(r["metric"]), float(r["value"][1])) for r in res),
              key=lambda x: -x[1])
for g, d in rows:
    print("  %-20s %.6f s" % (g, d))
print()

print("### 2) 慢组 vs 快组：同组内探针规则的 last_evaluation 间隔 ###")
# 组内串行 => A 组两条规则的求值时间戳不同（先后顺序）
# 组间并行 => A、B 组的时间戳错开，各自独立推进
res = query("prometheus_rule_last_evaluation_timestamp_seconds")
by_group = {}
for r in res:
    g = group_label(r["metric"])
    n = short_rule(r["metric"])
    by_group.setdefault(g, []).append((n, float(r["value"][1])))

for g in sorted(by_group):
    items = sorted(by_group[g], key=lambda x: x[1])
    print("  组 %s:" % g)
    for n, v in items:
        print("      %-40s %.6f" % (n, v))
    if len(items) > 1:
        delta = items[-1][1] - items[0][1]
        print("      -> 组内首末规则时间差: %.6f s（>0 说明串行）" % delta)
print()

print("### 3) 组内是否共享同一个求值时间戳？ ###")
for g, items in sorted(by_group.items()):
    vals = set(v for _, v in items)
    verdict = "✅ 完全一致（组内共享同一时间戳）" if len(vals) == 1 else \
              "❌ 有 %d 种不同时间戳" % len(vals)
    print("  %-20s %d 条规则 -> %s" % (g, len(items), verdict))
print()

print("### 4) 各组 eval 间隔配置（prometheus_rule_group_interval_seconds） ###")
res = query("prometheus_rule_group_interval_seconds")
for r in sorted(res, key=lambda x: group_label(x["metric"])):
    print("  %-20s %s s" % (group_label(r["metric"]), r["value"][1]))
print()

print("### 5) 规则求值总次数（判断各组是否都在推进） ###")
res = query("prometheus_rule_evaluations_total")
totals = {}
for r in res:
    g = group_label(r["metric"])
    totals[g] = totals.get(g, 0) + float(r["value"][1])
for g, t in sorted(totals.items()):
    print("  %-20s %.0f 次" % (g, t))
