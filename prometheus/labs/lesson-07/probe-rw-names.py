#!/usr/bin/env python3
"""核查：v3.14.0 里 remote write 指标的真实名字与语义。"""
from l7lib import qseries

print("=" * 70)
print("remote write 指标名核查（v3.14.0 本机实测）")
print("=" * 70)

candidates = [
    "prometheus_remote_storage_samples_in_total",
    "prometheus_remote_storage_samples_out_total",
    "prometheus_remote_storage_samples_total",
    "prometheus_remote_storage_samples_dropped_total",
    "prometheus_remote_storage_samples_failed_total",
    "prometheus_remote_storage_samples_retried_total",
    "prometheus_remote_storage_samples_pending",
    "prometheus_remote_storage_enqueue_retries_total",
    "prometheus_remote_storage_bytes_sent_total",
    "prometheus_remote_storage_bytes_total",
    "prometheus_remote_storage_metadata_bytes_total",
    "prometheus_remote_storage_shard_capacity",
    "prometheus_remote_storage_shards",
    "prometheus_remote_storage_shards_desired",
    "prometheus_remote_storage_max_samples_per_send",
]

print(f"\n{'指标名':58s} {'存在':6s} 值 / 标签")
print("-" * 100)
for m in candidates:
    r = qseries(m)
    if not r:
        print(f"{m:58s} {'NO':6s} ——")
        continue
    vals = []
    for s in r:
        labels = ",".join(f'{k}="{v}"' for k, v in s["metric"].items()
                          if k not in ("__name__",))
        vals.append(f'{s["value"][1]} {{{labels}}}' if labels else s["value"][1])
    print(f"{m:58s} {'YES':6s} {vals[0][:60]}")

print("\n" + "=" * 70)
print("结论说明")
print("=" * 70)
print("""
旧教程/网上资料常用的三个名字，在 v3.14.0 已不存在或改名：
  samples_out_total      -> 改成 samples_total
  samples_dropped_total  -> 已移除（改用 failed_total + enqueue_retries_total 观察）
  bytes_sent_total       -> 改成 bytes_total

注意 pending 与 total 都带 remote_name/url 标签，多 remote_write 目标时必须按 url 区分。
""")
