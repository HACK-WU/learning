#!/bin/bash
# 课 6 探索阶段：摸清可用的压缩度量手段
Q() { curl -s --max-time 10 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " X1 VM 自身暴露了哪些「存储/压缩」相关指标"
echo "=============================================="
curl -s --max-time 10 'http://localhost:8428/api/v1/label/__name__/values' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
import re
keys=['data_size','compr','bytes','rows','merge','part','storage','disk','size']
hit=[m for m in d if any(k in m.lower() for k in keys)]
print('总指标数:',len(d))
print('存储/压缩相关:')
for m in sorted(hit): print('  ',m)
" 2>&1

echo
echo "=============================================="
echo " X2 tsdb status：序列数与样本统计"
echo "=============================================="
curl -s --max-time 10 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -m json.tool 2>&1 | head -40

echo
echo "=============================================="
echo " X3 确认课 5 的 l05_bigload 数据是否还在"
echo "=============================================="
Q 'count(l05_bigload)' 2>&1 | head -c 300
echo
Q 'sum(vm_rows_inserted_total) by (type)' 2>&1 | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)['data']['result']
    for r in d: print('  %-16s %s' % (r['metric'].get('type','-'), r['value'][1]))
except Exception as e: print('  解析失败:',e)
" 2>&1

echo
echo "=============================================="
echo " X4 当前磁盘上 data 部分的实际占用"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
for t in timestamps.bin values.bin index.bin metaindex.bin items.bin lens.bin; do
  b=$(find data -name "$t" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  printf "  %-16s %9d 字节\n" "$t" "$b"
done
echo "  --- 合计 ---"
find data -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "  data/ 全部文件 %d 字节 (%.2f MB)\n", s, s/1048576}'

echo
echo "=============================================="
echo " X5 找一个有代表性的 part 看二进制布局"
echo "=============================================="
P=$(find data/data/small -mindepth 2 -maxdepth 2 -type d 2>/dev/null | head -1)
if [ -n "$P" ]; then
  echo "样本 part: $P"
  ls -la "$P"
  echo
  echo "-- timestamps.bin 前 64 字节 --"
  od -A d -t x1 "$P/timestamps.bin" 2>/dev/null | head -5
  echo
  echo "-- values.bin 前 64 字节 --"
  od -A d -t x1 "$P/values.bin" 2>/dev/null | head -5
else
  echo "未找到 small part"
fi
