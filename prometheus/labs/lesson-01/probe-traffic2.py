import json
import subprocess
import time
import urllib.parse
import urllib.request

PROM = "http://localhost:9095"


def query(q):
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(q)
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def show(title, qs):
    print("=== %s ===" % title)
    for q in qs:
        d = query(q)
        results = d["data"]["result"]
        if not results:
            print("  %-44s -> (空结果，序列已标记 stale)" % q)
            continue
        for r in results:
            m = r["metric"]
            label = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
            print("  %-44s %-46s -> %s" % (q, label[:46], r["value"][1]))
    print()


print("### 产生 20 次请求 ###")
for _ in range(20):
    p = subprocess.run(
        ["docker", "exec", "prometheus", "wget", "-qO-", "http://demo-app:8080/order"],
        capture_output=True, text=True,
    )
    print("  " + (p.stdout.strip() or "(500，无 body)"))

print()
print("等待 12 秒（scrape_interval=5s，至少 2 轮）")
time.sleep(12)
print()

show("计数器递增结果", [
    "demo_http_requests_total",
    "demo_http_request_status_total",
])

print("### 停掉 demo-app ###")
subprocess.run(["docker", "stop", "demo-app"], capture_output=True)
print("等待 20 秒")
time.sleep(20)
print()

show("停止 20 秒后", [
    "up",
    "demo_http_requests_total",
])
