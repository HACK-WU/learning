# -*- coding: utf-8 -*-
"""批量写入权衡模拟器 —— 纯标准库，可直接运行
对照 L12 知识点 1：批量写入与压缩
模拟的是「每条请求的固定开销 vs 批量大小」的权衡，
不是 InfluxDB 真实吞吐（真实值取决于网络、磁盘、CPU）。
"""
import time
import random

random.seed(20260901)

# ---------- 参数：一次 HTTP 请求的固定开销 ----------
FIXED_MS = 2.0          # 连接 + 头 + 服务端校验的固定开销（毫秒）
PER_POINT_MS = 0.002    # 每行 line protocol 的解析与写入开销（毫秒）
GZIP_RATIO = 0.2        # 压缩后体积比例（官方称最高 5x 提速，这里取 5x 体积压缩）
BYTES_PER_LINE = 120    # 每行 line protocol 大致字节数


def req_cost(n_points):
    """一次请求写 n_points 行的耗时（毫秒）"""
    return FIXED_MS + n_points * PER_POINT_MS


def throughput(total, batch):
    """用 batch 大小写 total 行，返回 (请求次数, 总耗时ms, 每秒点数)"""
    nreq = -(-total // batch)          # 向上取整
    total_ms = nreq * (FIXED_MS + batch * PER_POINT_MS)
    tps = total / (total_ms / 1000.0)
    return nreq, total_ms, tps


print("=" * 66)
print("实验 A：批量写入权衡模拟器")
print("=" * 66)
TOTAL = 1_000_000
print("场景：写入 {:,} 行 line protocol".format(TOTAL))
print("假设：每次请求固定开销 {:.1f} ms（连接+头+校验），每行解析 {:.3f} ms".format(
    FIXED_MS, PER_POINT_MS))
print("说明：固定开销是**拍脑袋假设值**；要抓的是**趋势**，不是绝对值\n")

print("[1] 批量大小 vs 吞吐（对照组：batch=1 为基线）")
print("    {:>10} {:>12} {:>14} {:>14} {:>10}".format(
    "批量大小", "请求次数", "总耗时(ms)", "点/秒", "相对基线"))
base_tps = None
results = []
for batch in (1, 10, 100, 1000, 5000, 10000, 50000, 100000):
    nreq, total_ms, tps = throughput(TOTAL, batch)
    if base_tps is None:
        base_tps = tps
    results.append((batch, nreq, total_ms, tps))
    print("    {:>10,} {:>12,} {:>14,.0f} {:>14,.0f} {:>9.1f}x".format(
        batch, nreq, total_ms, tps, tps / base_tps))

print("\n[2] 边际收益：每翻 10 倍批量，吞吐涨多少？")
for i in range(1, len(results)):
    prev_batch, _, _, prev_tps = results[i - 1]
    cur_batch, _, _, cur_tps = results[i]
    gain = cur_tps / prev_tps
    print("    batch {:>7,} -> {:>7,} ：吞吐 {:>12,.0f} -> {:>12,.0f}（{:.2f}x）".format(
        prev_batch, cur_batch, prev_tps, cur_tps, gain))

print("\n[3] 代价侧：批量越大，单批延迟与内存占用越高")
print("    {:>10} {:>16} {:>18} {:>16}".format(
    "批量大小", "单批延迟(ms)", "单批内存(MB,裸)", "gzip后(MB)"))
for batch in (1, 1000, 5000, 10000, 50000, 100000):
    latency = req_cost(batch)
    raw_mb = batch * BYTES_PER_LINE / 1024 / 1024
    gz_mb = raw_mb * GZIP_RATIO
    print("    {:>10,} {:>16.1f} {:>18.2f} {:>16.2f}".format(
        batch, latency, raw_mb, gz_mb))

print("\n[4] 官方推荐的 10,000 行 / 10MB 双阈值：哪个先到？")
for bytes_per_line in (60, 120, 300, 1000):
    mb_at_10k = 10000 * bytes_per_line / 1024 / 1024
    first = "行数先到（10,000 行）" if mb_at_10k < 10 else "体积先到（10 MB）"
    lines_at_10mb = int(10 * 1024 * 1024 / bytes_per_line)
    print("    每行 {:>5} 字节：10,000 行 = {:>6.1f} MB；10 MB = {:>7,} 行 -> {}".format(
        bytes_per_line, mb_at_10k, lines_at_10mb, first))

print("\n[5] flush_interval 的两难：低频小批量会怎样？")
print("    {:>18} {:>14} {:>16} {:>14}".format(
    "写入速率(点/秒)", "到达 5,000 行", "flush=1s 时", "flush=10s 时"))
for rate in (10, 100, 1000, 10000):
    sec_to_5k = 5000 / rate
    at_1s = min(rate * 1, 5000)
    at_10s = min(rate * 10, 5000)
    print("    {:>18,} {:>13.1f}s {:>15,}行 {:>13,}行".format(
        rate, sec_to_5k, at_1s, at_10s))
print("    低速场景（<500 点/秒）：靠 flush_interval 兜底，否则数据要等很久才发出去")
print("    高速场景：batch_size 先到，flush_interval 只是保险")
print("=" * 66)
