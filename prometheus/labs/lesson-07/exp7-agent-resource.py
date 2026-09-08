#!/usr/bin/env python3
"""
E7：Agent 模式的资源占用与"自监控必须外置"

两个要点：
  1) Agent 没有查询 API，所以你无法查它自己的 remote write 指标。
     解法：从外部抓它的 /metrics（这是运维上的硬要求）。
  2) 资源占用对比：Agent vs Server（相同抓取目标）。
"""
import json
import subprocess
import time
import urllib.request

AGENT = "http://localhost:19107"
SERVER = "http://localhost:19100"


def sh(cmd):
    return subprocess.run(["bash", "-lc", cmd], capture_output=True,
                          text=True).stdout.strip()


def docker_stats(name):
    out = sh(f'docker stats --no-stream --format "{{{{.MemUsage}}}}|{{{{.CPUPerc}}}}" {name}')
    return out


def metrics_text(host):
    with urllib.request.urlopen(f"{host}/metrics", timeout=20) as r:
        return r.read().decode()


def pick(text, name):
    for line in text.splitlines():
        if line.startswith(name + " ") or line.startswith(name + "{"):
            return line.split(" ")[-1]
    return None


print("=" * 78)
print("E7  Agent 资源占用 + 自监控必须外置")
print("=" * 78)

print("\n[1] 先证明：Agent 的 /metrics 仍然可抓（这是外置监控的基础）")
try:
    t = metrics_text(AGENT)
    n = len([l for l in t.splitlines() if l and not l.startswith("#")])
    print(f"    Agent /metrics 可访问，共 {n} 条指标")
except Exception as e:
    print(f"    Agent /metrics 不可访问: {e}")

print("\n[2] 从 /metrics 里直接读 Agent 的 remote write 状态（绕开查询 API）")
for m in ("prometheus_remote_storage_samples_total",
          "prometheus_remote_storage_samples_pending",
          "prometheus_remote_storage_samples_failed_total",
          "prometheus_remote_storage_shards",
          "prometheus_remote_storage_enqueue_retries_total"):
    v = pick(t, m)
    print(f"    {m:52s} = {v}")

print("\n[3] Agent 有没有本地 TSDB 指标？（预期：没有）")
for m in ("prometheus_tsdb_head_series",
          "prometheus_tsdb_head_chunks",
          "prometheus_tsdb_wal_storage_size_bytes"):
    v = pick(t, m)
    print(f"    {m:52s} = {v if v is not None else 'None（无此指标）'}")

print("\n[4] 资源占用对比（相同抓取目标：l7-app 507 条序列）")
print(f"    {'容器':16s} {'内存占用':>22s} {'CPU':>10s}")
for name in ("l7-prom", "l7-agent"):
    s = docker_stats(name)
    if "|" in s:
        mem, cpu = s.split("|")
        print(f"    {name:16s} {mem:>22s} {cpu:>10s}")
    else:
        print(f"    {name:16s} {s}")

print("\n[5] 磁盘占用对比")
for name, path in (("l7-prom", "/prometheus"), ("l7-agent", "/data-agent")):
    out = sh(f"docker exec {name} sh -c 'du -sh {path} 2>/dev/null' | tail -n 1")
    print(f"    {name:16s} {out}")

print("\n[6] 关键：Agent 的 WAL 保留多久（决定断网能扛多久）")
for m in ("prometheus_agent_retention_max_time_seconds",
          "prometheus_agent_retention_min_time_seconds"):
    v = pick(t, m)
    print(f"    {m:52s} = {v}")

print("\n[7] Server 侧同项对照")
ts = metrics_text(SERVER)
for m in ("prometheus_tsdb_head_series", "prometheus_tsdb_head_chunks"):
    print(f"    {m:52s} = {pick(ts, m)}")

print("\n" + "=" * 78)
print("E7 结论")
print("=" * 78)
print("""
1) Agent 的 /metrics 仍可抓取 —— 自监控必须外置到另一台 Prometheus
2) Agent 无本地 TSDB 指标（head_series / head_chunks 均不存在）
3) 内存/磁盘对比见上表
""")
