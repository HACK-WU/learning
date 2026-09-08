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


def docker_exec(*args):
    p = subprocess.run(["docker", "exec", *args], capture_output=True, text=True)
    return p.returncode, (p.stdout or "").strip(), (p.stderr or "").strip()


print("=== 检查各容器可用的 HTTP 工具 ===")
for c in ["l1-prometheus", "l1-pushgateway"]:
    code, out, err = docker_exec(c, "sh", "-c", "command -v curl wget busybox 2>/dev/null")
    print("  %-16s -> %s" % (c, out.replace("\n", " ") or "(none)"))

print()
print("=== 用 python3（demo-app 容器里确定有）发 DELETE ===")
code, out, err = docker_exec(
    "l1-demo-app", "python3", "-c",
    "import urllib.request;"
    "r=urllib.request.Request('http://pushgateway:9091/metrics/job/report-job',method='DELETE');"
    "print('HTTP',urllib.request.urlopen(r,timeout=10).status)",
)
print("  exit=%s out=%s err=%s" % (code, out, err[:200]))

print()
print("等待 8 秒让 Prometheus 抓到删除后的状态")
time.sleep(8)

d = query("job_last_run_timestamp_seconds")
if d["data"]["result"]:
    for r in d["data"]["result"]:
        print("  删除后仍能查到: %s -> %s" % (r["metric"], r["value"][1]))
else:
    print("  删除后查不到了 —— 只有显式 DELETE 才能让序列从 Pushgateway 消失")
