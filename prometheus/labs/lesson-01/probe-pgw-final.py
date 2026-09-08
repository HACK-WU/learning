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


def show(title, q):
    d = query(q)
    print("=== %s ===" % title)
    for r in d["data"]["result"]:
        m = r["metric"]
        label = ",".join("%s=%s" % (k, v) for k, v in sorted(m.items()) if k != "__name__")
        print("  %s -> %s" % (label, r["value"][1]))
    if not d["data"]["result"]:
        print("  (空)")
    print()


now = int(time.time())
payload = (
    "# TYPE batch_last_run_timestamp_seconds gauge\n"
    "# HELP batch_last_run_timestamp_seconds 批处理最后一次成功运行的时间戳\n"
    'batch_last_run_timestamp_seconds %d\n'
) % now

print("### 1) 批处理任务推送一次（模拟 cron job 跑完就退出） ###")
p = subprocess.run(
    ["docker", "exec", "-i", "prometheus", "wget", "-qO-",
     "--post-data", payload,
     "http://pushgateway:9091/metrics/job/nightly-batch"],
    capture_output=True, text=True,
)
print("  push exit=%s" % p.returncode)

print("等待 10 秒让 Prometheus 抓到")
time.sleep(10)

show("2) 查询推送的指标（注意 job 标签被改写了）", "batch_last_run_timestamp_seconds")

print("### 3) 任务早就退出了，但指标还在 ###")
print("  等待 30 秒后再查一次，值纹丝不动 —— 这就是'数据永不消失'")
time.sleep(30)
show("30 秒后", "batch_last_run_timestamp_seconds")

print("### 4) 正解：用 push_time_seconds 判断新鲜度 ###")
show("push_time_seconds", "push_time_seconds")

print("### 5) 显式 DELETE 才能让序列消失 ###")
p = subprocess.run(
    ["docker", "exec", "node-exporter", "sh", "-c",
     "command -v wget curl 2>/dev/null"],
    capture_output=True, text=True,
)
print("  node-exporter 容器可用工具: %s" % (p.stdout.strip() or "(none)"))

p = subprocess.run(
    ["docker", "exec", "demo-app", "python3", "-c",
     "import urllib.request;"
     "r=urllib.request.Request('http://pushgateway:9091/metrics/job/nightly-batch',method='DELETE');"
     "print(urllib.request.urlopen(r,timeout=10).status)"],
    capture_output=True, text=True,
)
print("  DELETE 返回: %s %s" % (p.stdout.strip(), p.stderr.strip()[:80]))

time.sleep(10)
show("6) 删除后", "batch_last_run_timestamp_seconds")
