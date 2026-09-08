"""E5 决定性对照：改变 --query.lookback-delta，边界是否随之移动？

这是证明「5 分钟」这个数字真实存在的唯一方法。

设计：
  1. 起一个对照组 Prometheus，--query.lookback-delta=30s
  2. 主组保持默认 5m
  3. 两组同时 break，然后查询「最后样本时刻之后 60 秒」的时刻
     → 30s 组应查不到（超出 30s），5m 组应能查到

注意：lookback 是向**过去**追溯。所以正确问法是：
  查询时刻 t，最后样本在 t - Δ。
  → Δ <= lookback 时命中最后样本；Δ > lookback 时无数据。

两组用同一份 app 数据（各自独立抓取，但数据形态相同）。
"""
import subprocess
import time

from l6lib import app_get, query, now

EXPR = "l6_concurrency"

print("== 1. 起对照组 Prometheus（lookback-delta=30s，宿主端口 19095） ==")
subprocess.run(
    "docker rm -f l6-prom-lb >/dev/null 2>&1; "
    "docker run -d --name l6-prom-lb --network lesson06-net "
    "-p 19095:9090 "
    "-v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml:ro "
    "prom/prometheus:v3.14.0 "
    "--config.file=/etc/prometheus/prometheus.yml "
    "--storage.tsdb.path=/prometheus "
    "--query.lookback-delta=30s",
    shell=True, capture_output=True)

print("   等待就绪...")
for i in range(40):
    r = subprocess.run(
        ["docker", "exec", "l6-prom-lb", "wget", "-qO-",
         "http://localhost:9090/-/ready"],
        capture_output=True, text=True)
    if "Ready" in r.stdout:
        print(f"   就绪（{i}s）")
        break
    time.sleep(1)

# 验证参数确实生效
r = subprocess.run(
    ["docker", "exec", "l6-prom-lb", "wget", "-qO-",
     "http://localhost:9090/api/v1/status/flags"],
    capture_output=True, text=True)
import json
print("   对照组 lookback-delta =",
      json.loads(r.stdout)["data"].get("query.lookback-delta"))

print()
print("== 2. 两组都等数据攒够 ==")
app_get("/unbreak")
app_get("/revive")
app_get("/cardinality?n=0")
time.sleep(20)


def query_on(container, expr, t=None):
    """在指定容器上查询。"""
    import urllib.parse
    url = f"http://localhost:9090/api/v1/query?query={urllib.parse.quote(expr)}"
    if t:
        url += f"&time={t}"
    r = subprocess.run(["docker", "exec", container, "wget", "-qO-", url],
                       capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
        if d.get("status") == "success" and d["data"]["result"]:
            return float(d["data"]["result"][0]["value"][1])
    except Exception:
        pass
    return None


print()
print("== 3. break，然后向「过去」追溯不同距离 ==")
print("break:", app_get("/break"))
time.sleep(15)      # 确保最后样本已固定

last = now()        # 近似最后样本时刻（break 前的最后一次成功抓取）
print(f"参考时刻 = {last:.3f}（break 之后，此处已无新样本）\n")

print(f'{"追溯Δ(秒)":>10} | {"5m组(默认)":>12} | {"30s组(对照)":>13}')
print("-" * 44)
for d in [5, 15, 25, 35, 60, 120, 240]:
    t = last - d
    v1 = query_on("l6-prom", EXPR, t)
    v2 = query_on("l6-prom-lb", EXPR, t)
    s1 = f"{v1:.0f}" if v1 is not None else "无数据"
    s2 = f"{v2:.0f}" if v2 is not None else "无数据"
    print(f"{d:>10} | {s1:>12} | {s2:>13}")

print()
print("unbreak:", app_get("/unbreak"))
