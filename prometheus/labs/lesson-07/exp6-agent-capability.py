#!/usr/bin/env python3
"""
E6：Agent 模式的能力边界（砍掉了什么、保留了什么）

用一个 Agent 实例（19107）与一个 Server 实例（19100）对照，
逐项实测哪些能力还在、哪些被砍。

实测项：
  1. 查询 API           → Agent 应拒绝
  2. /api/v1/targets    → 应保留（服务发现与抓取还在）
  3. /api/v1/status/config → 应保留
  4. remote write       → 应保留且在持续工作
  5. 本地 TSDB 指标     → Agent 不应有 prometheus_tsdb_head_series 等
  6. 规则               → 已在 E0 前实测：rule_files 直接拒绝启动
"""
import json
import urllib.request

AGENT = "http://localhost:19107"
SERVER = "http://localhost:19100"


def fetch(host, path, timeout=15):
    url = f"{host}{path}"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            body = r.read().decode()
            return r.status, body[:300]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]
    except Exception as e:
        return -1, f"{type(e).__name__}: {e}"


print("=" * 78)
print("E6  Agent 模式能力边界实测")
print("=" * 78)

checks = [
    ("/api/v1/query?query=up", "查询 API（瞬时查询）"),
    ("/api/v1/targets", "Targets 页面数据"),
    ("/api/v1/status/config", "运行时配置"),
    ("/api/v1/status/flags", "启动参数"),
    ("/api/v1/metadata", "元数据 API"),
    ("/api/v1/rules", "规则列表"),
    ("/api/v1/alertmanagers", "Alertmanager 列表"),
    ("/api/v1/labels", "标签列表（查询类）"),
]

print(f"\n{'能力':28s} {'Agent(19107)':>16s} {'Server(19100)':>16s}")
print("-" * 78)
results = {}
for path, desc in checks:
    ca, ba = fetch(AGENT, path)
    cs, bs = fetch(SERVER, path)
    results[desc] = (ca, cs)
    a_show = f"{ca}"
    s_show = f"{cs}"
    print(f"{desc:28s} {a_show:>16s} {s_show:>16s}")

print("\n" + "=" * 78)
print("逐项解读")
print("=" * 78)

for desc, (ca, cs) in results.items():
    if ca >= 400 and cs == 200:
        verdict = "❌ Agent 已禁用，Server 正常提供"
    elif ca == 200 and cs == 200:
        verdict = "✅ 两者都提供"
    elif ca == -1:
        verdict = "⚠ Agent 连接异常"
    else:
        verdict = f"   Agent={ca} Server={cs}"
    print(f"  {desc:28s} {verdict}")

print("\n" + "=" * 78)
print("关键指标对照：Agent 有没有本地 TSDB？")
print("=" * 78)

from l7lib import qcount, qnum

tsdb_metrics = [
    "prometheus_tsdb_head_series",
    "prometheus_tsdb_head_chunks",
    "prometheus_tsdb_wal_segment_current",
    "prometheus_tsdb_wal_storage_size_bytes",
    "prometheus_tsdb_symbol_table_size_bytes",
]

print(f"\n{'指标':46s} {'Agent':>12s} {'Server':>12s}")
print("-" * 78)
for m in tsdb_metrics:
    va = qnum(m, host=AGENT)
    vs = qnum(m, host=SERVER)
    fa = "None" if va is None else f"{va:.0f}"
    fs = "None" if vs is None else f"{vs:.0f}"
    print(f"{m:46s} {fa:>12s} {fs:>12s}")

print("\n" + "=" * 78)
print("Agent 的 remote write 在正常工作吗？")
print("=" * 78)
from l7lib import qnum as q
URL = 'http://l7-receiver:8080/api/v1/write'


def qlbl(m, host):
    try:
        from l7lib import qseries
        r = qseries(m, host=host)
        if not r:
            return None
        return float(r[0]["value"][1])
    except Exception:
        return None


for m in ("prometheus_remote_storage_samples_total",
          "prometheus_remote_storage_samples_pending",
          "prometheus_remote_storage_shards"):
    v = qlbl(m, AGENT)
    print(f"  {m:48s} = {'None' if v is None else f'{v:.0f}'}")

print("\n" + "=" * 78)
print("E6 结论")
print("=" * 78)
