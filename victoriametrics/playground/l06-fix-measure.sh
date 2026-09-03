#!/bin/bash
# 课 6 修正测量：用「查询出来的真实样本数」做基准，而非 vm_rows 累计计数
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " M1 为什么 104 倍是错的：vm_rows 是累计计数"
echo "=============================================="
echo "-- vm_rows 各 type（累计写入，含已合并的重复计数）--"
Q 'sum(vm_rows) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("  %-20s %12.0f" % (r["metric"].get("type","-"), float(r["value"][1])))'

echo
echo "-- vm_rows_merged_total（说明合并会重复计数）--"
Q 'sum(vm_rows_merged_total) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("  %-20s %12.0f" % (r["metric"].get("type","-"), float(r["value"][1])))'

echo
echo "  → 结论：vm_rows 累计了「写入次数」，一个样本被合并 N 次就计 N 次。"
echo "     不能拿它当「当前存量样本数」来算压缩率。"

echo
echo "=============================================="
echo " M2 正确基准：查询窗口内的真实样本数"
echo "=============================================="
echo "-- 查最近 1 小时，所有序列的总样本数 --"
SAMPLES=$(curl -s --max-time 60 --data-urlencode 'query=count_over_time(up[1h])' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
t=sum(float(r["value"][1]) for r in d)
print(int(t))' 2>/dev/null)
echo "  up[1h] 样本数: $SAMPLES"

echo
echo "-- 用更稳的方式：查一个我们自己写入的、已知规模的指标 --"
echo "   课 5 写入的 l05_bigload（200 条序列）"
Q 'count_over_time(l05_bigload[1h])' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
t=sum(float(r["value"][1]) for r in d)
print("  l05_bigload 在 1h 窗口内的样本数:", int(t))' 2>/dev/null

echo
echo "=============================================="
echo " M3 用「受控实验」测真实压缩率（最可靠）"
echo "=============================================="
echo "  做法：写入一批【已知规模、已知形态】的数据，"
echo "        然后只看这批数据带来的磁盘增量。"
echo "        这样分母分子都是干净的。"

echo
echo "-- 先看当前磁盘基线 --"
BASE=$(find data -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
echo "  基线: $BASE 字节"

echo
echo "-- 写入 1000 条【完全恒定】的值（压缩率应该极高）--"
TS=$(date +%s)
for i in $(seq 1 1000); do
  echo "l06_constant,idx=$i value=42.0 $((TS + i))"
done > /tmp/l06_const.txt
wc -l /tmp/l06_const.txt
curl -s -X POST --max-time 60 --data-binary @/tmp/l06_const.txt \
  'http://localhost:8428/api/v1/import/csv?format=1:time:unix_s,2:metric:l06_constant,3:value:last' \
  -o /dev/null -w '  CSV HTTP: %{http_code}\n' 2>&1

echo
echo "-- 改用 influx line protocol（课 4 证实 CSV 静默失败，不能信）--"
: > /tmp/l06_const.influx
for i in $(seq 1 1000); do
  echo "l06_constant,idx=$i value=42.0 $((TS + i))000000000"
done > /tmp/l06_const.influx
head -2 /tmp/l06_const.influx
curl -s -X POST --max-time 60 --data-binary @/tmp/l06_const.influx \
  'http://localhost:8428/write' -o /dev/null -w '  Influx HTTP: %{http_code}\n' 2>&1

echo
sleep 3
echo "-- 验证真的写进去了（用 VM 自身统计，不看 HTTP 码）--"
Q 'sum(vm_rows_inserted_total{type="influx"})' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  influx 累计写入行数:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
Q 'count(l06_constant)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  l06_constant 序列数:", int(float(d[0]["value"][1])) if d else "无")' 2>/dev/null
