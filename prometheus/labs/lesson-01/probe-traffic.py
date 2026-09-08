import json
import urllib.parse
import subprocess
import time
import urllib.request

BASE = "http://localhost:9095"


def query(q):
    url = BASE + "/api/v1/query?query=" + urllib.parse.quote(q)
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


print("=== 产生 20 次请求 ===")
for _ in range(20):
    out = subprocess.run(
        ["docker", "exec", "l1-prometheus", "wget", "-qO-", "http://demo-app:8080/order"],
        capture_output=True,
        text=True,
    )
    print(out.stdout.strip() or "(no output)")

print()
print("等待 12 秒让至少 2 轮抓取完成（scrape_interval=5s）")
time.sleep(12)

print()
print("=== demo_http_requests_total 当前值 ===")
d = query("demo_http_requests_total")
for r in d["data"]["result"]:
    m = r["metric"]
    print("endpoint=%-12s -> %s" % (m.get("endpoint"), r["value"][1]))

print()
print("=== demo_http_request_status_total 当前值 ===")
d = query("demo_http_request_status_total")
for r in d["data"]["result"]:
    m = r["metric"]
    print("status=%-6s -> %s" % (m.get("status"), r["value"][1]))
