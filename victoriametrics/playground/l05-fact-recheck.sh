#!/bin/bash
# 课 5 交付前事实复核：核对讲义引用的路径与实测数字
echo "=============================================="
echo " F1 宿主机数据目录真实层级（确认 data/data 是否重复）"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "-- playground/data 下第一层 --"
ls -la data/ 2>&1 | head -20
echo
echo "-- playground/data/data 是否存在 --"
if [ -d "data/data" ]; then
  echo "存在：playground/data/data"
  echo "-- playground/data/data 下第一层 --"
  ls -la data/data/ 2>&1 | head -20
else
  echo "不存在：playground/data/data（讲义中的 data/data/ 写法需修正）"
fi

echo
echo "=============================================="
echo " F2 容器内视角：/victoria-metrics-data 下第一层"
echo "=============================================="
docker exec vm-learn ls -la /victoria-metrics-data/ 2>&1 | head -20

echo
echo "=============================================="
echo " F3 精确定位 small / big / indexdb 的绝对路径"
echo "=============================================="
find data -maxdepth 4 -type d \( -name small -o -name big -o -name indexdb \) -print 2>/dev/null

echo
echo "=============================================="
echo " F4 文件类型统计复核（对照讲义第 3 步表格）"
echo "=============================================="
for t in timestamps.bin values.bin index.bin metaindex.bin items.bin lens.bin; do
  n=$(find data -name "$t" -type f 2>/dev/null | wc -l)
  b=$(find data -name "$t" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  printf "%-16s %3d 个  %8d 字节\n" "$t" "$n" "$b"
done

echo
echo "=============================================="
echo " F5 当前 part 数与 big 目录状态"
echo "=============================================="
if [ -d "data/data/small" ]; then BASE="data/data"; else BASE="data"; fi
for p in "$BASE/small" "$BASE/big"; do
  [ -d "$p" ] && echo "$p : $(find "$p" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l) 个 part"
done
