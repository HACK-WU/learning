#!/bin/bash
# 课 6 开课环境检查：容器状态 + 端口 + 数据基线
echo "=============================================="
echo " E1 容器状态"
echo "=============================================="
docker ps -a --format 'table {{.Names}}\t{{.Status}}' 2>&1

echo
echo "=============================================="
echo " E2 VM 端口可达性（8428 / 2003 / 4242 / 4243）"
echo "=============================================="
for p in 8428 2003 4243; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$p/health" 2>/dev/null)
  echo "port $p -> HTTP $code"
done

echo
echo "=============================================="
echo " E3 VM 版本与关键启动参数"
echo "=============================================="
docker inspect vm-learn --format '{{range .Args}}{{println .}}{{end}}' 2>&1 | head -30

echo
echo "=============================================="
echo " E4 当前数据基线（课 5 结束时）"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "-- 顶层 --"
ls data/ 2>&1
echo
echo "-- data/data 下 --"
ls -la data/data/ 2>&1 | head -15
echo
echo "-- small / big / indexdb 的 part 数 --"
for p in data/data/small data/data/big data/data/indexdb; do
  [ -d "$p" ] && echo "$p : $(find $p -mindepth 2 -maxdepth 2 -type d 2>/dev/null | wc -l) 个 part"
done

echo
echo "=============================================="
echo " E5 文件类型统计（课 6 压缩率测量的起点）"
echo "=============================================="
for t in timestamps.bin values.bin index.bin metaindex.bin items.bin lens.bin; do
  n=$(find data -name "$t" -type f 2>/dev/null | wc -l)
  b=$(find data -name "$t" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  printf "%-16s %3d 个  %9d 字节\n" "$t" "$n" "$b"
done

echo
echo "=============================================="
echo " E6 活跃序列数与磁盘总量"
echo "=============================================="
curl -s --max-time 5 'http://localhost:8428/api/v1/query?query=sum(vm_cache_entries%7Btype%3D%22storage%2Fhour_metric_ids%22%7D)' 2>&1 | head -c 300
echo
du -sh data/ 2>&1
