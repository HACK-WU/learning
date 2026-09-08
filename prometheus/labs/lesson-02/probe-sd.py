import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9096"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def query(q):
    return get("/api/v1/query?query=" + urllib.parse.quote(q))


print("=== 1) file-sd-demo 的 active targets ===")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    if t["labels"]["job"] == "file-sd-demo":
        print("  %-26s health=%s" % (t["scrapeUrl"], t["health"]))
        print("      labels=%s" % json.dumps(t["labels"], ensure_ascii=False))

print()
print("=== 2) 被 relabel keep 丢弃的 target ===")
d2 = get("/api/v1/targets?state=dropped")
found = False
for t in d2["data"]["droppedTargets"]:
    labels = t.get("labels") or t.get("discoveredLabels") or {}
    if labels.get("job") == "file-sd-demo":
        print("  %s" % json.dumps(t, ensure_ascii=False)[:300])
        found = True
if not found:
    print("  (dropped 列表里没有 file-sd-demo 的记录)")

print()
print("=== 3) 提升后的业务标签是否落到样本上 ===")
for q in ['app_build_info{job="file-sd-demo"}']:
    d = query(q)
    for r in d["data"]["result"]:
        print("  %s" % json.dumps(r["metric"], ensure_ascii=False))

print()
print("=== 4) relabel-target-demo 的 __address__ 改写结果 ===")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    if t["labels"]["job"] == "relabel-target-demo":
        print("  scrapeUrl=%-30s labels=%s" % (t["scrapeUrl"], json.dumps(t["labels"], ensure_ascii=False)))
