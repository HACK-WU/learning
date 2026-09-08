#!/usr/bin/env python3
"""E0：验证 remote write 全链路是否真的通。"""
import time

from l7lib import PROM, RECV, qcount, qnum, query, recv_reset, recv_stats

print("=" * 70)
print("E0  remote write 链路连通性")
print("=" * 70)

# receiver 设为正常模式
print("\n[1] 把 receiver 设为 ok 模式，重置统计")
print("   ", recv_reset())
print("   ", {"mode": "ok"} if True else "")

time.sleep(20)

print("\n[2] receiver 侧统计（收到了吗？解压出多少字节？）")
s = recv_stats()
for k in ("mode", "requests", "accepted", "rejected",
          "bytes_compressed", "bytes_decompressed"):
    print(f"    {k:22s} = {s.get(k)}")

print("\n[3] Prometheus 侧 remote write 队列指标")
metrics = {
    "prometheus_remote_storage_samples_pending": "队列中等待发送的样本数",
    "prometheus_remote_storage_samples_in_total": "进入队列的样本总数",
    "prometheus_remote_storage_samples_out_total": "实际发出的样本总数",
    "prometheus_remote_storage_samples_failed_total": "发送失败的样本总数",
    "prometheus_remote_storage_samples_dropped_total": "被丢弃的样本总数",
    "prometheus_remote_storage_shards": "当前 shard 数",
    "prometheus_remote_storage_shards_max": "shard 上限",
    "prometheus_remote_storage_shards_min": "shard 下限",
    "prometheus_remote_storage_highest_timestamp_in_seconds": "已入队的最新样本时间",
    "prometheus_remote_storage_queue_highest_sent_timestamp_seconds": "已发送的最新样本时间",
    "prometheus_remote_storage_bytes_sent_total": "已发送字节数",
    "prometheus_remote_storage_sent_batch_duration_seconds_count": "发送批次计数",
}
vals = {}
for m, desc in metrics.items():
    v = qnum(m)
    vals[m] = v
    vs = "None" if v is None else f"{v:.0f}"
    print(f"    {m:58s} = {vs:>12s}   # {desc}")

print("\n[4] 关键判据")
ok = True

if s.get("requests", 0) > 0:
    print(f"    [PASS] receiver 收到了 {s['requests']} 次 write 请求")
else:
    print("    [FAIL] receiver 一次都没收到 —— 链路不通")
    ok = False

if s.get("bytes_decompressed", 0) > 0:
    print(f"    [PASS] 解压出 {s['bytes_decompressed']} 字节（snappy 解压成功）")
else:
    print("    [FAIL] 解压字节为 0 —— 解压方式不对或没有数据")
    ok = False

in_t = vals.get("prometheus_remote_storage_samples_in_total")
out_t = vals.get("prometheus_remote_storage_samples_out_total")
if in_t and in_t > 0:
    print(f"    [PASS] Prometheus 侧已入队 {in_t:.0f} 个样本")
else:
    print("    [FAIL] Prometheus 侧入队样本为 0")
    ok = False

if out_t and in_t and out_t > 0:
    loss = (in_t - out_t) / in_t * 100
    print(f"    [INFO] in={in_t:.0f} out={out_t:.0f} 差值={in_t-out_t:.0f} ({loss:.1f}%)")

shards = vals.get("prometheus_remote_storage_shards")
smax = vals.get("prometheus_remote_storage_shards_max")
if shards:
    print(f"    [INFO] 当前 shards={shards:.0f} / max={smax:.0f}")

print("\n[5] 本地也存了吗？（server 模式本地+远程双写）")
local = qcount("l7_card_balance")
print(f"    本地 l7_card_balance 序列数 = {local}")

print("\n" + "=" * 70)
print("E0 结论:", "PASS 链路通" if ok else "FAIL 需要排查")
print("=" * 70)
