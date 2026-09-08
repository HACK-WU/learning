import json
import subprocess
import time
import urllib.parse
import urllib.request

PUSHGW = "http://localhost:9091"
PROM = "http://localhost:9095"


def http_get(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.read().decode("utf-8")


def query(q):
    url = PROM + "/api/v1/query?query=" + urllib.parse.quote(q)
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


print("=== 1) 模拟批处理任务推送一次结果 ===")
payload = (
    "# TYPE batch_last_success_timestamp_seconds gauge\n"
    "# HELP batch_last_success_timestamp_seconds 批处理任务最后一次成功的时间戳\n"
    'batch_last_success_timestamp_seconds{job="nightly-batch"} 1788490900\n'
    "# TYPE batch_records_processed_total counter\n"
    "# HELP batch_records_processed_total 批处理累计处理记录数\n"
    'batch_records_processed_total{job="nightly-batch"} 4321\n'
)
p = subprocess.run(
    [
        "docker",
        "exec",
        "-i",
        "l1-prometheus",
        "wget",
        "-qO-",
        "--post-data",
        payload,
        "http://pushgateway:9091/metrics/job/nightly-batch",
    ],
    capture_output=True,
    text=True,
)
print("push exit=%s" % p.returncode)

print()
print("等待 8 秒让 Prometheus 抓到 Pushgateway")
time.sleep(8)

print()
print("=== 2) 查询推送的指标（注意 instance 与 pushed 标签） ===")
for q in ["batch_records_processed_total", "batch_last_success_timestamp_seconds"]:
    d = query(q)
    for r in d["data"]["result"]:
        print("  %-40s metric=%s value=%s" % (q, r["metric"], r["value"][1]))
    if not d["data"]["result"]:
        print("  %-40s -> (空)" % q)

print()
print("=== 3) 现在停掉所有容器再重启 Pushgateway，看数据是否还在 ===")
subprocess.run(["docker", "restart", "l1-pushgateway"], capture_output=True)
print("已重启 Pushgateway（未做任何推送）")
time.sleep(10)

d = query("batch_records_processed_total")
if d["data"]["result"]:
    for r in d["data"]["result"]:
        print("  重启后仍能查到: %s -> %s" % (r["metric"], r["value"][1]))
else:
    print("  重启后查不到了（Pushgateway 默认不持久化）")

print()
print("=== 4) Pushgateway 自身的 push_time_seconds ===")
d = query("push_time_seconds")
for r in d["data"]["result"]:
    print("  %s -> %s" % (r["metric"], r["value"][1]))
