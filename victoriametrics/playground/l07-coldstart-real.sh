#!/bin/bash
# 课 7 实验 6：真正的冷启动 —— 删除缓存文件后重启
# 这是验证「缓存价值」的决定性实验
Q() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
g() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)["data"]["result"]
  print("%.0f" % float(d[0]["value"][1]) if d else 0)
except: print(0)'; }

bench() {
  local label="$1"; local q="$2"
  local times=""
  for i in 1 2 3 4 5; do
    t=$(curl -s --max-time 120 --data-urlencode "query=$q" http://localhost:8428/api/v1/query \
        -o /dev/null -w '%{time_total}' 2>&1)
    times="$times $t"
  done
  echo $times | tr ' ' '\n' | sort -n | awk -v L="$label" '{a[NR]=$1} END {printf "  %-26s 中位 %.4f s  (全部:", L, a[int(NR/2)+1]; for(i=1;i<=NR;i++) printf " %s", a[i]; print ")"}'
}

cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

echo "=============================================="
echo " T1 删缓存前：热状态基准"
echo "=============================================="
echo "  缓存条目: $(g 'sum(vm_cache_entries)')"
echo "  缓存字节: $(g 'sum(vm_cache_size_bytes)')"
echo "  data/cache 大小: $(du -sh data/cache 2>/dev/null | cut -f1)"
echo
bench "10000序列全查"  'l07_margin2_value'
bench "正则全匹配"     '{__name__=~"^l07_.*$"}'
bench "聚合查询"       'sum(l07_margin2_value) by (idx)'

echo
echo "=============================================="
echo " T2 停止容器 + 删除缓存 + 重启"
echo "=============================================="
echo "  备份缓存目录（可恢复）..."
cp -r data/cache /tmp/l07_cache_backup 2>/dev/null && echo "  已备份到 /tmp/l07_cache_backup"
echo
docker stop vm-learn 2>&1 | tail -1
echo "  删除 data/cache/* ..."
rm -rf data/cache/* 2>&1
ls -la data/cache/ 2>&1 | head -5
echo
echo "  重启容器..."
docker start vm-learn 2>&1 | tail -1
echo "  等待就绪..."
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8428/health' 2>/dev/null)
  if [ "$code" = "200" ]; then echo "  第 ${i}×2 秒：VM 已就绪"; break; fi
  sleep 2
done

echo
echo "=============================================="
echo " T3 真·冷启动状态"
echo "=============================================="
echo "  缓存条目: $(g 'sum(vm_cache_entries)')"
echo "  缓存字节: $(g 'sum(vm_cache_size_bytes)')"
echo "  tsid 命中率:"
Q '1 - (sum(vm_cache_misses_total{type="storage/tsid"})/sum(vm_cache_requests_total{type="storage/tsid"}))' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
if d:
  for r in d: print("    %.2f%%" % (float(r["value"][1])*100))
else: print("    无请求（缓存刚重建）")' 2>/dev/null

echo
echo "  -- 冷查询 --"
bench "10000序列全查(冷)" 'l07_margin2_value'
bench "正则全匹配(冷)"    '{__name__=~"^l07_.*$"}'
bench "聚合查询(冷)"      'sum(l07_margin2_value) by (idx)'

echo
echo "  -- 再跑一遍，看回温 --"
bench "10000序列全查(温)" 'l07_margin2_value'
bench "正则全匹配(温)"    '{__name__=~"^l07_.*$"}'

echo
echo "=============================================="
echo " T4 数据完整性验证（删缓存不能丢数据）"
echo "=============================================="
echo "  totalSeries:"
curl -s --max-time 20 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c 'import json,sys; print("    ", json.load(sys.stdin)["data"].get("totalSeries"))' 2>/dev/null
echo "  l07_margin2 样本数:"
Q 'count_over_time(l07_margin2_value[2h])' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    ", int(sum(float(r["value"][1]) for r in d)))' 2>/dev/null
echo "  课 6 的数据还在吗（l06r_random）:"
Q 'count_over_time(l06r_random_value[2h])' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    ", int(sum(float(r["value"][1]) for r in d)))' 2>/dev/null

echo
echo "=============================================="
echo " T5 缓存是否自动重建"
echo "=============================================="
sleep 10
echo "  10 秒后缓存条目: $(g 'sum(vm_cache_entries)')"
echo "  data/cache 是否重建: $(ls data/cache/ 2>/dev/null | wc -l) 个文件/目录"
