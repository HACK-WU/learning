"""诊断：staleness marker 到底插没插？

矛盾点：
  - 理论：/kill（抓取成功）→ 插 stale marker；/break（抓取失败）→ 不插
  - 实测：两者表现完全一致，都在 Δ=10s 时查不到

排查方向：
  1. 我的 app 在 kill 后是否真的返回 200？（可能 Flask 报错了）
  2. Prometheus 是否真的抓取成功？看 target 的 health/lastError
  3. TSDB 里到底存了什么？用区间查询看原始样本点（含 staleness marker
     在 API 里表现为特殊的 StaleNaN 值）
"""
import json
import time

from l6lib import _wget, app_get, query, query_range, now

EXPR = "l6_concurrency"


def show_targets():
    d = json.loads(_wget("/api/v1/targets?state=active"))
    for t in d["data"]["activeTargets"]:
        if t["labels"].get("job") == "l6-app":
            print(f'   job={t["labels"].get("job")} health={t.get("health")} '
                  f'lastError="{t.get("lastError","")}" '
                  f'lastScrapeDuration={t.get("lastScrapeDuration")}')


def raw_samples(start, end, step="5s"):
    """区间查询，返回所有样本点。"""
    r = query_range(EXPR, start, end, step)
    if not r:
        return []
    return r[0]["values"]


print("== 1. app 在 kill / break 后的真实 HTTP 响应 ==")
import subprocess
for act in ["/revive", "/unbreak", None, "/kill", None, "/revive", "/break", None]:
    if act:
        print(f"   {act} → {app_get(act)}")
        time.sleep(6)
    else:
        out = subprocess.run(
            ["docker", "exec", "l6-prom", "wget", "-S", "-O", "-",
             "http://l6-app:8080/metrics"],
            capture_output=True, text=True)
        code = [l for l in out.stderr.splitlines() if "HTTP/" in l]
        print(f"   /metrics 响应头: {code}")
        print(f"   响应体前 120 字符: {out.stdout[:120]!r}")
        show_targets()
