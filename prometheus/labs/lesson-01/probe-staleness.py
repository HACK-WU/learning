import json
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "http://localhost:9095"
QUERIES = [
    "up",
    "demo_http_requests_total",
    'up{job="demo-app"}',
]


def query(q):
    url = BASE + "/api/v1/query?query=" + urllib.parse.quote(q)
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def show(title):
    print("--- %s ---" % title)
    for q in QUERIES:
        d = query(q)
        results = d["data"]["result"]
        if not results:
            print("  %-28s -> (空结果，序列已标记 stale)" % q)
            continue
        for r in results:
            m = r["metric"]
            ts, val = r["value"]
            print("  %-28s -> job=%-10s value=%s @ ts=%s" % (q, m.get("job", "-"), val, ts))
    print()


show("停止 demo-app 之前")

print("=== docker stop l1-demo-app ===")
subprocess.run(["docker", "stop", "l1-demo-app"], capture_output=True)
print()

print("等待 20 秒（scrape_interval=5s，lookback delta 默认 5 分钟）")
time.sleep(20)
print()

show("停止 demo-app 20 秒后")
