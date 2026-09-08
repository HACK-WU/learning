import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"


def query(q):
    url = BASE + "/api/v1/query?" + urllib.parse.urlencode({"query": q})
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))["data"]["result"]


def names(pattern):
    """列出匹配的所有指标名。"""
    res = query('count({__name__=~"%s"}) by (__name__)' % pattern)
    return sorted(r["metric"]["__name__"] for r in res)


print("### 所有 prometheus_rule_* 指标 ###")
for n in names("prometheus_rule_.*"):
    print("  " + n)
print()

print("### 是否存在 last_evaluation_timestamp ###")
res = query('count({__name__=~"prometheus_rule_.*timestamp.*"}) by (__name__)')
if res:
    for r in res:
        print("  ✅", r["metric"]["__name__"])
else:
    print("  ❌ 不存在任何 prometheus_rule_*timestamp* 指标")
print()

print("### prometheus_rule_last_evaluation_timestamp_seconds 直接查 ###")
res = query("prometheus_rule_last_evaluation_timestamp_seconds")
print("  返回 %d 条" % len(res))
print()

print("### 所有 prometheus_sd / prometheus_rule_group_* 指标 ###")
for n in names("prometheus_rule_group_.*"):
    print("  " + n)
print()

print("### ALERTS / ALERTS_FOR_STATE 是否存在 ###")
for n in names("ALERTS.*"):
    print("  " + n)
res = query("ALERTS")
print("  ALERTS 返回 %d 条" % len(res))
res = query("ALERTS_FOR_STATE")
print("  ALERTS_FOR_STATE 返回 %d 条" % len(res))
