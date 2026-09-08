import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9096"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def query(q):
    return get("/api/v1/query?query=" + urllib.parse.quote(q))


print("=== 1) honor-true 抓到的样本，job 标签到底是什么？ ===")
d = query('app_build_info{instance="i-am-the-real-instance:9999"}')
for r in d["data"]["result"]:
    print("  %s" % json.dumps(r["metric"], ensure_ascii=False, sort_keys=True))
if not d["data"]["result"]:
    print("  (无结果)")

print()
print("=== 2) 用 target 自己给的 job 值去查 ===")
d = query('app_build_info{job="i-am-the-real-job"}')
for r in d["data"]["result"]:
    print("  %s" % json.dumps(r["metric"], ensure_ascii=False, sort_keys=True))
if not d["data"]["result"]:
    print("  (无结果)")

print()
print("=== 3) honor-true 的 target 是否健康？ ===")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    if t["labels"]["job"] == "honor-true":
        print("  health=%s  lastError=%s" % (t["health"], t.get("lastError", "")))
        print("  scrapeUrl=%s" % t["scrapeUrl"])

print()
print("=== 4) up 指标：三个 honor job 的存活状态 ===")
d = query('up{job=~"honor-.*"}')
for r in d["data"]["result"]:
    m = r["metric"]
    print("  job=%-14s instance=%-34s -> %s"
          % (m.get("job"), m.get("instance"), r["value"][1]))
