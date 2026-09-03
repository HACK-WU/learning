#!/bin/bash
# 课 7 实验 3：冷启动 + 内存模型 + 容量规划参数
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
g() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)["data"]["result"]
  print("%.0f" % float(d[0]["value"][1]) if d else 0)
except: print(0)'; }

echo "=============================================="
echo " M1 内存全景（VM 自己报的）"
echo "=============================================="
echo "-- vm_allowed_memory_bytes（VM 认为自己能用多少）--"
g 'vm_allowed_memory_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "-- vm_available_memory_bytes（系统可用）--"
g 'vm_available_memory_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "-- process_resident_memory_bytes（实际 RSS）--"
g 'process_resident_memory_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "-- go_memstats_sys_bytes（Go 向 OS 申请的总量）--"
g 'go_memstats_sys_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "-- go_memstats_heap_inuse_bytes（堆在用）--"
g 'go_memstats_heap_inuse_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "-- go_memstats_next_gc_bytes（下次 GC 触发点）--"
g 'go_memstats_next_gc_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'

echo
echo "=============================================="
echo " M2 缓存占了多少内存（分层明细）"
echo "=============================================="
Q 'sum(vm_cache_size_bytes) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
tot=0
rows=[]
for r in d:
    v=float(r["value"][1]); tot+=v
    rows.append((r["metric"].get("type","-"), v))
rows.sort(key=lambda x:-x[1])
for t,v in rows:
    if v>0: print("    %-36s %12.2f MB" % (t, v/1048576))
print("    %-36s %12.2f MB" % ("缓存合计", tot/1048576))
' 2>/dev/null

echo
echo "-- 缓存合计占 RSS 的比例 --"
CACHE=$(Q 'sum(vm_cache_size_bytes)' | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(float(d[0]["value"][1]))' 2>/dev/null | cut -d. -f1)
RSS=$(g 'process_resident_memory_bytes' | cut -d. -f1)
if [ -n "$CACHE" ] && [ "$RSS" -gt 0 ]; then
  echo "    缓存 $CACHE / RSS $RSS = $(echo "scale=1;$CACHE*100/$RSS"|bc)%"
fi

echo
echo "=============================================="
echo " M3 内存的「固定开销」—— 三个 64MB 缓存"
echo "=============================================="
echo "  storage/metricIDs    : 67108864 字节 = 64.00 MB（预分配上限）"
echo "  storage/metricName   : 67108864 字节 = 64.00 MB"
echo "  storage/tsid         : 67108864 字节 = 64.00 MB"
echo
echo "  ⚠️ 注意：这是【已用】还是【预分配】？看 entries 数："
Q 'vm_cache_entries{type=~"storage/metricIDs|storage/metricName|storage/tsid"}' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d: print("    %-26s %8d 条目" % (r["metric"].get("type","-"), int(float(r["value"][1]))))' 2>/dev/null
echo
echo "  entries 才 2 万条，但占了 64MB → 说明是【预分配的固定容量】，"
echo "  不是按条目数计费。这就是 VM 的「内存地板」。"

echo
echo "=============================================="
echo " M4 GC 行为（Go runtime）"
echo "=============================================="
echo "  GC 次数: $(g 'go_gc_duration_seconds_count')"
echo "  GC 累计耗时: $(g 'go_gc_duration_seconds_sum') s"
echo "  GC CPU 占比: $(g 'go_memstats_gc_cpu_fraction')"
echo "  goroutine 数: $(g 'go_goroutines')"

echo
echo "=============================================="
echo " M5 容量规划基线：当前每序列占多少内存"
echo "=============================================="
SERIES=$(g 'sum(vm_cache_entries{type="storage/hour_metric_ids"})')
RSS=$(g 'process_resident_memory_bytes')
if [ "$SERIES" -gt 0 ] && [ "$RSS" -gt 0 ]; then
  echo "    活跃序列数: $SERIES"
  echo "    RSS: $RSS 字节 ($(echo "scale=2;$RSS/1048576"|bc) MB)"
  echo "    → 每序列: $(echo "scale=1;$RSS/$SERIES"|bc) 字节"
fi
echo
echo "  磁盘侧："
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
DISK=$(find data -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
echo "    磁盘占用: $DISK 字节 ($(echo "scale=2;$DISK/1048576"|bc) MB)"
if [ "$SERIES" -gt 0 ]; then
  echo "    → 每序列磁盘: $(echo "scale=1;$DISK/$SERIES"|bc) 字节"
fi

echo
echo "=============================================="
echo " M6 冷启动验证：重启容器后缓存清空"
echo "=============================================="
echo "  ⚠️ 这会重启 VM，丢失内存中的未落盘数据（少量）。"
echo "     本次先【不执行】，仅记录方法："
echo "     docker restart vm-learn && sleep 30"
echo "     然后对比重启前后的 vm_cache_entries 与查询耗时"
