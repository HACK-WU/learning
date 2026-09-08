import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"


def query(q):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": q})
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]


def gl(m):
    g = m.get("rule_group", "?")
    return g.split(";")[-1] if ";" in g else g


print("### 关键对比：整组耗时 vs 组内各规则耗时之和 ###")
print("若组内串行 => last_duration（整组墙钟）≈ last_rule_duration_sum（各规则之和）")
print()

res_sum = query("prometheus_rule_group_last_rule_duration_sum_seconds")
res_dur = query("prometheus_rule_group_last_duration_seconds")
sums = {gl(r["metric"]): float(r["value"][1]) for r in res_sum}
durs = {gl(r["metric"]): float(r["value"][1]) for r in res_dur}

print("  %-20s %14s %14s %10s" % ("组", "整组墙钟", "各规则之和", "差值"))
for g in sorted(durs):
    d = durs[g]
    s = sums.get(g, 0.0)
    print("  %-20s %14.6f %14.6f %10.6f" % (g, d, s, d - s))
print()

print("### 各组最后求值时间戳（判断是否并行推进） ###")
res = query("prometheus_rule_group_last_evaluation_timestamp_seconds")
rows = sorted(((gl(r["metric"]), float(r["value"][1])) for r in res), key=lambda x: x[1])
import time
now = time.time()
print("  当前系统时间: %.3f" % now)
for g, ts in rows:
    print("  %-20s %.3f  (距今 %.1f s)" % (g, ts, now - ts))
print()

print("### ALERTS 与 ALERTS_FOR_STATE ###")
for name in ["ALERTS", "ALERTS_FOR_STATE"]:
    res = query(name)
    print("  %s -> %d 条" % (name, len(res)))
    for r in res:
        m = r["metric"]
        print("      alertname=%-22s alertstate=%-10s value=%s"
              % (m.get("alertname", "?"), m.get("alertstate", "?"), r["value"][1]))
print()

print("### 各告警规则当前是否活跃 ###")
res = query("prometheus_rule_evaluation_duration_seconds")
for r in res:
    print("  %s" % r["metric"])
