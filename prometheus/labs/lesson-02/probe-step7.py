import json
import urllib.parse
import subprocess
import time
import urllib.request

BASE = "http://localhost:9096"


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


print("=== 当前 app-order-1 的状态 ===")
d = get("/api/v1/targets?state=active")
for t in d["data"]["activeTargets"]:
    if "app-order-1" in t["labels"].get("instance", ""):
        print("  job=%-22s health=%-6s scrapeUrl=%s"
              % (t["labels"]["job"], t["health"], t["scrapeUrl"]))

print()
print("=== 容器状态 ===")
p = subprocess.run(["docker", "ps", "-a", "--filter", "name=app-order-1",
                    "--format", "{{.Names}}\t{{.Status}}"], capture_output=True, text=True)
print("  " + p.stdout.strip())

print()
print("=== honor-normal 的 up 值 ===")
with urllib.request.urlopen(BASE + "/api/v1/query?query=" +
                            urllib.parse.quote('up{job="honor-normal"}'), timeout=10) as r:
    d = json.loads(r.read().decode())
    for res in d["data"]["result"]:
        print("  %s -> %s" % (res["metric"], res["value"][1]))
