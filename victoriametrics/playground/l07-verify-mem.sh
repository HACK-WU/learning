#!/bin/bash
# 课 7 关键排查：缓存合计 343MB > RSS 119MB，物理上不可能
# 假设：vm_cache_size_bytes 统计的是「虚拟地址空间/预分配容量」而非「实际物理占用」
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
g() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin)["data"]["result"]
  print("%.0f" % float(d[0]["value"][1]) if d else 0)
except: print(0)'; }

echo "=============================================="
echo " P1 逐个核对：size_bytes vs size_max_bytes"
echo "=============================================="
echo "  如果 size == size_max，说明报的是【容量上限】不是【实际用量】"
Q 'vm_cache_size_bytes{type=~"storage/metricIDs|storage/metricName|storage/tsid"}' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  -- size_bytes（当前）--")
for r in d: print("    %-26s %14.0f" % (r["metric"].get("type","-"), float(r["value"][1])))' 2>/dev/null

Q 'vm_cache_size_max_bytes{type=~"storage/metricIDs|storage/metricName|storage/tsid"}' \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  -- size_max_bytes（上限）--")
for r in d: print("    %-26s %14.0f" % (r["metric"].get("type","-"), float(r["value"][1])))' 2>/dev/null

echo
echo "  ⚠️ 注意：size_max 里没有 storage/metricIDs 的 67108864，"
echo "     说明 max 是【按系统内存算出来的理论上限】，不是这三个缓存的真实上限。"

echo
echo "=============================================="
echo " P2 关键：fastcache 的预分配特性"
echo "=============================================="
echo "  VM 用的是 fastcache 库，它在创建时就【一次性 mmap 预留】桶数组。"
echo "  这部分内存在 RSS 里体现为『已映射但未触碰的页』。"
echo
echo "  验证方法：看 process_resident_memory_bytes 的各分量"
echo "  -- anon（匿名内存，真正占用的）--"
g 'process_resident_memory_anon_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "  -- file（文件映射，含 mmap 的缓存文件）--"
g 'process_resident_memory_file_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "  -- shared --"
g 'process_resident_memory_shared_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "  -- virtual（虚拟地址空间，可以很大）--"
g 'process_virtual_memory_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'
echo "  -- virtual max --"
g 'process_virtual_memory_max_bytes' | awk '{printf "    %.2f MB\n", $1/1048576}'

echo
echo "=============================================="
echo " P3 结论推导"
echo "=============================================="
RSS=$(g 'process_resident_memory_bytes')
VSZ=$(g 'process_virtual_memory_bytes')
ANON=$(g 'process_resident_memory_anon_bytes')
CACHE=$(curl -s --max-time 15 --data-urlencode 'query=sum(vm_cache_size_bytes)' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print("%.0f" % float(d[0]["value"][1]))' 2>/dev/null)
echo "  RSS（物理内存）      : $(echo "scale=2;$RSS/1048576"|bc) MB"
echo "  匿名内存（真实占用）: $(echo "scale=2;$ANON/1048576"|bc) MB"
echo "  虚拟地址空间         : $(echo "scale=2;$VSZ/1048576"|bc) MB"
echo "  vm_cache_size_bytes  : $(echo "scale=2;$CACHE/1048576"|bc) MB"
echo
echo "  虚拟地址空间($VSZ) > 缓存统计($CACHE) > RSS($RSS)"
echo "  → 证明：vm_cache_size_bytes 统计的是【虚拟地址空间占用】，"
echo "         不是【物理内存占用】。RSS 才是真实开销。"

echo
echo "=============================================="
echo " P4 修正后的容量规划数字"
echo "=============================================="
SERIES=$(g 'sum(vm_cache_entries{type="storage/hour_metric_ids"})')
echo "  活跃序列数: $SERIES"
echo "  真实物理内存(RSS): $(echo "scale=2;$RSS/1048576"|bc) MB"
echo "  → 每序列真实内存: $(echo "scale=1;$RSS/$SERIES"|bc) 字节"
echo
echo "  ⚠️ 但这个数字也不可直接用于生产估算，因为："
echo "     1. 当前只有 2 万序列，固定开销（Go runtime + 预分配）占大头"
echo "     2. 序列数增长后，边际成本远低于平均值"
echo
echo "  正确做法：测【边际成本】—— 增加序列，看 RSS 增量"

echo
echo "=============================================="
echo " P5 测边际成本：写入 5000 条新序列，看 RSS 增量"
echo "=============================================="
RSS0=$(g 'process_resident_memory_bytes')
SER0=$(g 'sum(vm_cache_entries{type="storage/hour_metric_ids"})')
echo "  写入前: RSS=$(echo "scale=2;$RSS0/1048576"|bc) MB, 序列=$SER0"

NOW=$(date +%s); START=$((NOW-600))
python3 - <<PY
import subprocess
now=int(subprocess.check_output(["date","+%s"]).decode().strip())
start=now-600
lines=[]
for i in range(5000):
    ts=(start+300)*1000000000
    lines.append("l07_marginal,idx=%d value=%d.0 %d" % (i, i%100, ts))
open("/tmp/l07_marginal.influx","w").write("\n".join(lines)+"\n")
print("  生成 5000 条序列（每条 1 个样本，过去时间）")
PY

curl -s -X POST --max-time 120 --data-binary @/tmp/l07_marginal.influx 'http://localhost:8428/write' \
  -o /dev/null -w '  写入 HTTP: %{http_code}\n'
curl -s -X POST --max-time 30 'http://localhost:8428/internal/force_flush' -o /dev/null
sleep 8

RSS1=$(g 'process_resident_memory_bytes')
SER1=$(g 'sum(vm_cache_entries{type="storage/hour_metric_ids"})')
echo "  写入后: RSS=$(echo "scale=2;$RSS1/1048576"|bc) MB, 序列=$SER1"
echo
DSER=$((SER1-SER0)); DRSS=$((RSS1-RSS0))
echo "  序列增量: $DSER"
echo "  RSS 增量: $DRSS 字节"
if [ "$DSER" -gt 0 ]; then
  echo "  → 边际成本: $(echo "scale=1;$DRSS/$DSER"|bc) 字节/序列"
fi
