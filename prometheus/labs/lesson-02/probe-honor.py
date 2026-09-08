import json
import urllib.parse
import urllib.request

BASE = "http://localhost:9096"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def query(q):
    return get("/api/v1/query?query=" + urllib.parse.quote(q))


print("=== 1) 应用自己暴露的原始文本（看它自带哪些标签） ===")
with urllib.request.urlopen("http://localhost:9096/api/v1/targets?state=active", timeout=10) as r:
    pass

print()
print("=== 2) honor-false vs honor-true 抓同一个冲突 target ===")
for job in ["honor-false", "honor-true", "honor-normal"]:
    d = query('app_build_info{job="%s"}' % job)
    print("--- job=%s ---" % job)
    for r in d["data"]["result"]:
        m = r["metric"]
        print("  %s" % json.dumps(m, ensure_ascii=False, sort_keys=True))
    if not d["data"]["result"]:
        print("  (无结果)")
    print()

print("=== 3) 目标页上看到的 instance（honor_labels 不影响 target 层） ===")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    if t["labels"]["job"].startswith("honor-"):
        print("  job=%-14s scrapeUrl=%-32s instance=%s"
              % (t["labels"]["job"], t["scrapeUrl"], t["labels"].get("instance")))
