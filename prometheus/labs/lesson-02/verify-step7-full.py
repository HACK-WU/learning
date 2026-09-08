import json
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9096"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def query(q):
    with urllib.request.urlopen(BASE + "/api/v1/query?query=" + urllib.parse.quote(q), timeout=10) as r:
        return json.loads(r.read().decode())


print("=== 停止 app-order-1 ===")
subprocess.run(["docker", "stop", "app-order-1"], capture_output=True)
time.sleep(25)

print("active 列表中的 app-order-1:")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    if "app-order-1" in t["labels"].get("instance", ""):
        print("  job=%-22s health=%s" % (t["labels"]["job"], t["health"]))

print()
print("up 与业务序列:")
for q in ['up{job="honor-normal"}', 'app_build_info{job="honor-normal"}']:
    res = query(q)["data"]["result"]
    print("  %-40s -> %s" % (q, res[0]["value"][1] if res else "(空)"))

print()
print("=== 恢复 ===")
subprocess.run(["docker", "start", "app-order-1"], capture_output=True)
time.sleep(15)
res = query('up{job="honor-normal"}')["data"]["result"]
print("  up -> %s" % (res[0]["value"][1] if res else "(空)"))
