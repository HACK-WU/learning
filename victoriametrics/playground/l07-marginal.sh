#!/bin/bash
# 课 7 重测边际成本：用 tsdb status 的 totalSeries 作权威基准
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
TS() { curl -s --max-time 20 'http://localhost:8428/api/v1/status/tsdb' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"].get("totalSeries",0))' 2>/dev/null; }
RSSV() { curl -s --max-time 15 --data-urlencode 'query=process_resident_memory_bytes' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print("%.0f" % float(d[0]["value"][1]) if d else 0)' 2>/dev/null; }

echo "=============================================="
echo " G1 基线（写入 l07_marginal 5000 条之后的状态）"
echo "=============================================="
S0=$(TS); R0=$(RSSV)
echo "  totalSeries: $S0"
echo "  RSS: $R0 字节 ($(echo "scale=2;$R0/1048576"|bc) MB)"

echo
echo "=============================================="
echo " G2 追加 10000 条新序列（每条 1 个样本）"
echo "=============================================="
python3 - <<'PY'
import subprocess
now=int(subprocess.check_output(["date","+%s"]).decode().strip())
start=now-300
lines=[]
for i in range(10000):
    ts=(start+60)*1000000000
    lines.append("l07_margin2,idx=%d value=%d.0 %d" % (i, i%100, ts))
open("/tmp/l07_margin2.influx","w").write("\n".join(lines)+"\n")
print("  生成 10000 条序列")
PY

curl -s -X POST --max-time 180 --data-binary @/tmp/l07_margin2.influx 'http://localhost:8428/write' \
  -o /dev/null -w '  写入 HTTP: %{http_code}\n'
curl -s -X POST --max-time 30 'http://localhost:8428/internal/force_flush' -o /dev/null

echo "  等待缓存与索引追上..."
sleep 20

S1=$(TS); R1=$(RSSV)
echo "  totalSeries: $S1"
echo "  RSS: $R1 字节 ($(echo "scale=2;$R1/1048576"|bc) MB)"

echo
echo "=============================================="
echo " G3 计算边际成本"
echo "=============================================="
DS=$((S1-S0)); DR=$((R1-R0))
echo "  序列增量: $DS"
echo "  RSS 增量: $DR 字节 ($(echo "scale=3;$DR/1048576"|bc) MB)"
if [ "$DS" -gt 0 ]; then
  echo "  → 每序列边际内存: $(echo "scale=1;$DR/$DS"|bc) 字节"
  echo "  → 每 100 万序列需要: $(echo "scale=1;$DR*1000000/$DS/1048576"|bc) MB"
fi

echo
echo "=============================================="
echo " G4 磁盘侧边际成本"
echo "=============================================="
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
Q 'sum(vm_data_size_bytes)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("  vm_data_size_bytes:", "%.0f" % float(d[0]["value"][1]) if d else "无")' 2>/dev/null
DISK=$(find data -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
echo "  磁盘总量: $DISK 字节 ($(echo "scale=2;$DISK/1048576"|bc) MB)"
if [ "$S1" -gt 0 ]; then
  echo "  → 每序列磁盘(平均): $(echo "scale=1;$DISK/$S1"|bc) 字节"
fi

echo
echo "=============================================="
echo " G5 验证：写入前后查询耗时是否被稀释"
echo "=============================================="
bench() {
  local label="$1"; local q="$2"
  local times=""
  for i in 1 2 3; do
    t=$(curl -s --max-time 60 --data-urlencode "query=$q" http://localhost:8428/api/v1/query \
        -o /dev/null -w '%{time_total}' 2>&1)
    times="$times $t"
  done
  printf "  %-32s 中位 %s s\n" "$label" "$(echo $times | tr ' ' '\n' | sort -n | awk '{a[NR]=$1} END {print a[int(NR/2)+1]}')"
}
bench "单序列精确查询" 'l07_marginal_value{idx="0"}'
bench "5000 序列全查"  'l07_marginal_value'
bench "10000 序列全查" 'l07_margin2_value'

echo
echo "=============================================="
echo " G6 内存水位：VM 认为能用多少"
echo "=============================================="
echo "  vm_allowed_memory_bytes (VM 自认可用):"
Q 'vm_allowed_memory_bytes' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    %.2f MB" % (float(d[0]["value"][1])/1048576))' 2>/dev/null
echo "  vm_available_memory_bytes (系统可用):"
Q 'vm_available_memory_bytes' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print("    %.2f MB" % (float(d[0]["value"][1])/1048576))' 2>/dev/null
echo
echo "  → allowed 通常 = 系统内存的 60%（VM 的默认策略）"
echo "    这台机器可用 31.8 GB，allowed 19.1 GB，比值 $(echo "scale=3;19091/31819"|bc)"
