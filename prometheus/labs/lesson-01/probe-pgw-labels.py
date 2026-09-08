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


now = int(time.time())
payload = (
    "# TYPE batch_last_run_timestamp_seconds gauge\n"
    'batch_last_run_timestamp_seconds %d\n'
) % now

p = subprocess.run(
    ["docker", "exec", "-i", "prometheus", "wget", "-qO-",
     "--post-data", payload,
     "http://pushgateway:9091/metrics/job/nightly-batch/instance/batch-01"],
    capture_output=True, text=True,
)
print("push exit=%s (带 grouping key instance=batch-01)" % p.returncode)
time.sleep(10)

print()
print("=== 1) Pushgateway 自己暴露的原始文本 ===")
with urllib.request.urlopen("http://localhost:9091/metrics", timeout=10) as r:
    text = r.read().decode("utf-8")
for line in text.splitlines():
    if "batch_last_run" in line or line.startswith("push_time_seconds"):
        print("  " + line)

print()
print("=== 2) Prometheus 里该序列的完整标签集 ===")
d = query("batch_last_run_timestamp_seconds")
for r in d["data"]["result"]:
    print("  metric =", r["metric"])
    print("  value  =", r["value"][1])
