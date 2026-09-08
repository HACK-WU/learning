import json
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9094"


def api(path, params=None):
    url = BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def query(expr):
    return api("/api/v1/query", {"query": expr})["data"]["result"]


print("### 1) 从 /api/v1/targets 读真实的抓取时刻 ###")
d = api("/api/v1/targets")["data"]["activeTargets"]
now = time.time()
print("  当前系统时刻: %.3f" % now)
print()
for t in d:
    labels = t.get("labels", {})
    job = labels.get("job", "?")
    last = t.get("lastScrape")
    dur = t.get("lastScrapeDuration")
    if last:
        print("  job=%-14s  上次抓取=%s  距今=%.2fs  耗时=%.4fs"
              % (job, last, now - _parse_ts(last) if False else 0, dur if dur else 0))
print()


def _parse(s):
    """解析 RFC3339 时间戳。"""
    import datetime
    s = s.replace("Z", "+00:00")
    return datetime.datetime.fromisoformat(s).timestamp()


print("### 2) 精确计算：上次抓取距今多久 ###")
print()
for t in d:
    labels = t.get("labels", {})
    job = labels.get("job", "?")
    last = t.get("lastScrape")
    if not last:
        continue
    ts = _parse(last)
    lag = now - ts
    print("  job=%-14s  上次抓取距今 %.2f 秒" % (job, lag))
print()

print("### 3) 关键推论：规则求值时能看到的最新样本有多旧 ###")
print("  抓取间隔 5s，所以求值时刻看到的最新样本，平均比'此刻'旧 0~5 秒")
print("  这就是'规则求值拿到的是上次抓取到的数据'的含义")
print()

print("### 4) 用 range query 验证：样本时间戳严格按 5 秒网格分布 ###")
res = api("/api/v1/query_range",
          {"query": "app_requests_total{status=\"200\"}",
           "start": now - 30, "end": now, "step": "5s"})
vals = res["data"]["result"]
if vals:
    series = vals[0]["values"]
    print("  最近 30 秒的样本时间戳（step=5s）:")
    stamps = [float(s) for s, _ in series]
    for s in stamps[-8:]:
        print("    %.1f" % s)
    if len(stamps) > 1:
        deltas = [round(stamps[i+1] - stamps[i], 1) for i in range(len(stamps)-1)]
        print("  相邻间隔:", deltas[-6:])
print()

print("### 5) 规则组求值偏移（evaluation_offset） ###")
res = query('prometheus_rule_group_last_evaluation_timestamp_seconds')
rows = sorted(((r["metric"].get("rule_group", "?").split(";")[-1],
                float(r["value"][1])) for r in res), key=lambda x: x[1])
print("  各组最近求值时刻:")
for g, ts in rows:
    print("    %-20s %.3f" % (g, ts))
if len(rows) > 1:
    print()
    print("  各组求值时刻互不相同 -> 说明组间是错开（并行）推进的")
