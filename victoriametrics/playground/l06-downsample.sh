#!/bin/bash
# 课 6：降采样实验 + 压缩率全景
Q() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " S1 降采样是否已启用（当前容器没开 -downsampling.period）"
echo "=============================================="
Q 'vm_downsampling_partitions_scheduled' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  已调度的降采样分区数:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
Q 'vm_downsampling_partitions_scheduled_size_bytes' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  降采样数据字节数:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
echo
echo "  → 全 0，说明当前【未启用】降采样（-retentionPeriod=1d 太短，用不上）"

echo
echo "=============================================="
echo " S2 用 vmctl/export 演示「降采样的效果」"
echo "=============================================="
echo "  思路：降采样 = 用更粗的粒度存老数据。"
echo "  我们不重启容器（会丢数据），改用【查询侧】模拟同样效果："
echo "  对比「原始粒度」与「5分钟粒度」的数据量差异。"
echo

echo "-- 原始粒度：l06r_random 在 30 分钟内的样本数 --"
Q 'count_over_time(l06r_random_value[30m])' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
t=sum(float(r["value"][1]) for r in d)
print("  原始样本数:", int(t))' 2>/dev/null

echo "-- 降采样到 5 分钟粒度后：每 5 分钟只留 1 个点 --"
Q 'count_over_time(last_over_time(l06r_random_value[5m])[30m:5m])' 2>&1 \
  | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)["data"]["result"]
    t=sum(float(r["value"][1]) for r in d)
    print("  5分钟粒度样本数:", int(t))
except Exception as e: print("  查询失败:", e)' 2>/dev/null

echo
echo "=============================================="
echo " S3 压缩率全景（最终数字）"
echo "=============================================="
echo "-- 全局 ZSTD 累计压缩比 --"
Q 'sum(vm_zstd_block_original_bytes_total)/sum(vm_zstd_block_compressed_bytes_total)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d:
    v=float(r["value"][1]); print("  %.3f 倍 (省 %.1f%%)" % (v,(1-1/v)*100))' 2>/dev/null

echo "-- 各 type 的 data size --"
Q 'sum(vm_data_size_bytes) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d:
    v=float(r["value"][1])
    if v>0: print("  %-22s %12.0f 字节" % (r["metric"].get("type","-"), v))' 2>/dev/null

echo
echo "=============================================="
echo " S4 时间戳列的压缩（delta-of-delta 的证据）"
echo "=============================================="
Q 'sum(vm_timestamps_bytes_saved_total)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("  时间戳编码累计节省: %.0f 字节" % float(r["value"][1]))' 2>/dev/null
Q 'sum(vm_timestamps_blocks_merged_total)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("  已合并的时间戳块数: %.0f" % float(r["value"][1]))' 2>/dev/null

cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo
echo "-- 磁盘上 timestamps.bin 实际总量 --"
find data -name 'timestamps.bin' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "  %.0f 字节\n", s+0}'

echo
echo "=============================================="
echo " S5 回答课 5 伏笔：每块 115.7 行为什么压得那么小"
echo "=============================================="
echo "  课 5 实测：合并后每块平均 115.7 行，而磁盘上每个 part 才几十 KB。"
echo "  现在可以回答了："
echo "   - 恒定值：每样本 1.02 字节（ZSTD 后）"
echo "   - 缓变值：每样本 3.97 字节"
echo "   - 随机值：每样本 6.12 字节"
echo "  真实监控数据绝大多数是【缓变】的（CPU 在 30%-40% 之间晃），"
echo "  所以实际每样本约 2-4 字节，115.7 行 ≈ 300-450 字节，确实很小。"
