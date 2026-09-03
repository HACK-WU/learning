#!/bin/bash
# 课 7 实验 5：冷启动 —— 重启容器，看缓存清空后查询慢多少
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
    t=$(curl -s --max-time 90 --data-urlencode "query=$q" http://localhost:8428/api/v1/query \
        -o /dev/null -w '%{time_total}' 2>&1)
    times="$times $t"
  done
  echo $times | tr ' ' '\n' | sort -n | awk -v L="$label" '{a[NR]=$1} END {printf "  %-28s 中位 %.4f s  (全部:", L, a[int(NR/2)+1]; for(i=1;i<=NR;i++) printf " %s", a[i]; print ")"}'
}

echo "=============================================="
echo " R1 重启前：热缓存状态"
echo "=============================================="
echo "  缓存条目总数: $(g 'sum(vm_cache_entries)')"
echo "  缓存 size_bytes: $(g 'sum(vm_cache_size_bytes)')"
echo "  tsid 缓存命中率:"
Q '1 - (sum(vm_cache_misses_total{type="storage/tsid"})/sum(vm_cache_requests_total{type="storage/tsid"}))' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    %.2f%%" % (float(r["value"][1])*100))' 2>/dev/null

echo
echo "  -- 热查询基准 --"
bench "10000序列全查(热)" 'l07_margin2_value'
bench "正则匹配(热)"      '{__name__=~"^l07_.*$"}'

echo
echo "=============================================="
echo " R2 重启容器（清空所有内存缓存）"
echo "=============================================="
echo "  docker restart vm-learn ..."
docker restart vm-learn 2>&1 | tail -1
echo "  等待 VM 启动完成（最多 90 秒）..."
for i in $(seq 1 45); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8428/health' 2>/dev/null)
  if [ "$code" = "200" ]; then echo "  第 ${i}×2 秒：VM 已就绪"; break; fi
  sleep 2
done

echo
echo "=============================================="
echo " R3 重启后：冷缓存状态"
echo "=============================================="
echo "  缓存条目总数: $(g 'sum(vm_cache_entries)')"
echo "  缓存 size_bytes: $(g 'sum(vm_cache_size_bytes)')"
echo "  tsid 缓存命中率:"
Q '1 - (sum(vm_cache_misses_total{type="storage/tsid"})/sum(vm_cache_requests_total{type="storage/tsid"}))' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d:
  try: print("    %.2f%%" % (float(r["value"][1])*100))
  except: print("    无数据（还没有请求）")' 2>/dev/null

echo
echo "  -- 冷查询（第一次，缓存全空）--"
bench "10000序列全查(冷)" 'l07_margin2_value'
bench "正则匹配(冷)"      '{__name__=~"^l07_.*$"}'

echo
echo "  -- 再跑一次，看是否已回温 --"
bench "10000序列全查(温)" 'l07_margin2_value'

echo
echo "=============================================="
echo " R4 重启后数据完整性验证"
echo "=============================================="
echo "  totalSeries:"
curl -s --max-time 20 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c 'import json,sys; print("    ", json.load(sys.stdin)["data"].get("totalSeries"))' 2>/dev/null
echo "  l07_margin2 样本数:"
Q 'count_over_time(l07_margin2_value[2h])' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    ", int(sum(float(r["value"][1]) for r in d)))' 2>/dev/null
echo "  ZSTD 压缩比:"
Q 'sum(vm_zstd_block_original_bytes_total)/sum(vm_zstd_block_compressed_bytes_total)' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    %.3f 倍" % float(d[0]["value"][1]))' 2>/dev/null
