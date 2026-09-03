#!/bin/bash
# 课 6 关键探索：VM 直接暴露的 ZSTD 压缩统计（黄金数据源）
Q() { curl -s --max-time 10 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
FMT='import json,sys
d=json.load(sys.stdin)["data"]["result"]
if not d: print("  (无数据)")
for r in d:
    m=r["metric"]; lbl=" ".join("%s=%s"%(k,v) for k,v in sorted(m.items()) if k!="__name__")
    try: val=float(r["value"][1])
    except: val=0
    print("  %-52s %14.0f" % (lbl or "-", val))
'

echo "=============================================="
echo " Z1 ZSTD 压缩统计（全局）"
echo "=============================================="
echo "-- 原始字节数（压缩前）--"
Q 'sum(vm_zstd_block_original_bytes_total)' | python3 -c "$FMT"
echo "-- 压缩后字节数 --"
Q 'sum(vm_zstd_block_compressed_bytes_total)' | python3 -c "$FMT"
echo "-- 压缩调用次数 --"
Q 'sum(vm_zstd_block_compress_calls_total)' | python3 -c "$FMT"
echo "-- 解压调用次数 --"
Q 'sum(vm_zstd_block_decompress_calls_total)' | python3 -c "$FMT"

echo
echo "-- 按 type 拆分（这是关键：谁在压缩什么）--"
Q 'sum(vm_zstd_block_original_bytes_total) by (type)' | python3 -c "$FMT"
echo "---"
Q 'sum(vm_zstd_block_compressed_bytes_total) by (type)' | python3 -c "$FMT"
echo "---"
Q 'sum(vm_zstd_block_compress_calls_total) by (type)' | python3 -c "$FMT"

echo
echo "=============================================="
echo " Z2 实时压缩率（原始 vs 压缩后）"
echo "=============================================="
Q 'sum(vm_zstd_block_original_bytes_total) / sum(vm_zstd_block_compressed_bytes_total)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d:
    v=float(r["value"][1]); print("  全局压缩比: %.3f  (即省了 %.1f%%)" % (v,(1-1/v)*100 if v else 0))'

echo
echo "=============================================="
echo " Z3 时间戳专项：delta 编码节省了多少"
echo "=============================================="
echo "-- vm_timestamps_bytes_saved_total --"
Q 'vm_timestamps_bytes_saved_total' | python3 -c "$FMT"
echo "-- vm_timestamps_blocks_merged_total --"
Q 'vm_timestamps_blocks_merged_total' | python3 -c "$FMT"

echo
echo "=============================================="
echo " Z4 存储总量与数据大小"
echo "=============================================="
Q 'vm_data_size_bytes' | python3 -c "$FMT"
echo "---"
Q 'sum(vm_data_size_bytes) by (type)' | python3 -c "$FMT"
echo "-- vm_rows（总样本行数）--"
Q 'sum(vm_rows) by (type)' | python3 -c "$FMT"
echo "-- vm_rows_merged_total（合并处理过的行）--"
Q 'sum(vm_rows_merged_total) by (type)' | python3 -c "$FMT"

echo
echo "=============================================="
echo " Z5 降采样相关指标"
echo "=============================================="
Q 'vm_downsampling_partitions_scheduled' | python3 -c "$FMT"
echo "---"
Q 'vm_downsampling_partitions_scheduled_size_bytes' | python3 -c "$FMT"
