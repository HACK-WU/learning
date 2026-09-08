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


def push(payload, url_path):
    p = subprocess.run(
        [
            "docker", "exec", "-i", "l1-prometheus",
            "wget", "-qO-", "--post-data", payload,
            "http://pushgateway:9091/metrics/" + url_path,
        ],
        capture_output=True, text=True,
    )
    return p.returncode


print("=== 1) 推送一次，然后什么都不做，等 35 秒 ===")
now = int(time.time())
payload = (
    "# TYPE job_last_run_timestamp_seconds gauge\n"
    'job_last_run_timestamp_seconds{job="report-job"} %d\n'
) % now
print("push exit=%s, pushed ts=%d" % (push(payload, "job/report-job"), now))

time.sleep(35)

d = query("job_last_run_timestamp_seconds")
for r in d["data"]["result"]:
    print("  35 秒后仍可查到: %s -> %s" % (r["metric"], r["value"][1]))

print()
print("=== 2) 该任务早已结束，但 Pushgateway 仍在汇报它 ===")
print("  这就是'数据永不消失'陷阱：任务死了，指标还活着，告警永远不恢复")

print()
print("=== 3) 正解：用 push_time_seconds 判断推送的新鲜度 ===")
d = query("push_time_seconds")
for r in d["data"]["result"]:
    pushed_at = float(r["value"][1])
    print("  %s -> push_time=%d (距今 %d 秒)" % (r["metric"].get("job"), pushed_at, time.time() - pushed_at))

print()
print("=== 4) 正确的删除方式：DELETE 而非等它过期 ===")
p = subprocess.run(
    ["docker", "exec", "l1-prometheus", "wget", "-qO-", "--method=DELETE",
     "http://pushgateway:9091/metrics/job/report-job"],
    capture_output=True, text=True,
)
print("delete exit=%s" % p.returncode)
time.sleep(8)
d = query("job_last_run_timestamp_seconds")
if d["data"]["result"]:
    print("  删除后仍能查到（说明删除未生效）")
else:
    print("  删除后查不到了 —— 只有显式 DELETE 才能让序列消失")
