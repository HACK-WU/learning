import json
import urllib.parse
import shutil
import subprocess
import time
import urllib.request

BASE = "http://localhost:9096"
TARGETS = "/mnt/d/projects/learning/prometheus/labs/lesson-02/sd/targets.json"
BACKUP = "/mnt/d/projects/learning/prometheus/labs/lesson-02/sd/targets.json.bak"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def query(q):
    with urllib.request.urlopen(BASE + "/api/v1/query?query=" + urllib.parse.quote(q), timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


print("=== 停掉 app-order-1 容器 ===")
subprocess.run(["docker", "stop", "app-order-1"], capture_output=True)
time.sleep(20)

d = get("/api/v1/targets")
print("  active 中的 app-order-1:")
found = False
for t in d["data"]["activeTargets"]:
    if "app-order-1" in t["labels"].get("instance", ""):
        print("    job=%s health=%s" % (t["labels"]["job"], t["health"]))
        found = True
if not found:
    print("    (已不在 active 列表)")

print()
print("  dropped 中的 app-order-1:")
d2 = get("/api/v1/targets?state=dropped")
for t in d2["data"]["droppedTargets"]:
    labels = t.get("labels") or t.get("discoveredLabels") or {}
    if "app-order-1" in str(labels.get("instance", "")):
        print("    job=%s" % labels.get("job"))

print()
print("=== 关键：目标从 SD 里消失，vs 抓取失败，结果一样吗？ ===")
for q in ['up{job="honor-normal"}', 'app_build_info{job="honor-normal"}']:
    d = query(q)
    res = d["data"]["result"]
    print("  %-42s -> %s" % (q, res[0]["value"][1] if res else "(空)"))

print()
print("=== 恢复 ===")
subprocess.run(["docker", "start", "app-order-1"], capture_output=True)
shutil.copy(BACKUP, TARGETS)
time.sleep(12)
for q in ['up{job="honor-normal"}']:
    d = query(q)
    res = d["data"]["result"]
    print("  %-42s -> %s" % (q, res[0]["value"][1] if res else "(空)"))
