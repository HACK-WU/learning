#!/bin/bash
# 课 6 精测：三组数据形态各自的磁盘占用（分批改入，逐组隔离测量）
# 改进点：时间戳用【过去】的时间（NOW-600 起），避免落在未来查不到
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

Q() { curl -s --max-time 20 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " 实验设计（修正版）"
echo "=============================================="
echo "  三组，每组 2000 条序列 × 20 个时间点 = 40000 样本"
echo "  时间戳：过去 (NOW-1200) 起，10 秒等间隔 → 一定可查"
echo "  A l06r_const  : 恒定 42.0"
echo "  B l06r_slow   : 缓变 +1"
echo "  C l06r_random : 随机 0-1000000"

echo
echo "=============================================="
echo " 生成数据"
echo "=============================================="
python3 - <<PY
import random
random.seed(1234)
import subprocess
now = int(subprocess.check_output(["date","+%s"]).decode().strip())
start = now - 1200   # 20 分钟前开始，确保全在过去
lines = {"l06r_const":[], "l06r_slow":[], "l06r_random":[]}
for i in range(2000):
    for t in range(20):
        ts = (start + t*10) * 1000000000
        lines["l06r_const"].append("l06r_const,idx=%d value=42.0 %d" % (i, ts))
        lines["l06r_slow"].append("l06r_slow,idx=%d value=%d.0 %d" % (i, 100+i+t, ts))
        lines["l06r_random"].append("l06r_random,idx=%d value=%d.0 %d" % (i, random.randint(0,1000000), ts))
for name, ls in lines.items():
    open("/tmp/%s.influx" % name, "w").write("\n".join(ls) + "\n")
    print("  %-14s %6d 行" % (name, len(ls)))
print("  时间范围: %d ~ %d (过去)" % (start, start+190))
PY

echo
echo "=============================================="
echo " 逐组写入 + 隔离测量"
echo "=============================================="
declare -A BEFORE_TS BEFORE_VAL BEFORE_ZO BEFORE_ZC
declare -A AFTER_TS AFTER_VAL AFTER_ZO AFTER_ZC

get_ts() { find data -name 'timestamps.bin' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}'; }
get_val() { find data -name 'values.bin' -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}'; }
get_zo() { curl -s --max-time 20 --data-urlencode 'query=sum(vm_zstd_block_original_bytes_total)' http://localhost:8428/api/v1/query | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null; }
get_zc() { curl -s --max-time 20 --data-urlencode 'query=sum(vm_zstd_block_compressed_bytes_total)' http://localhost:8428/api/v1/query | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null; }

for g in l06r_const l06r_slow l06r_random; do
  echo
  echo "---------- $g ----------"
  BEFORE_TS[$g]=$(get_ts); BEFORE_VAL[$g]=$(get_val)
  BEFORE_ZO[$g]=$(get_zo); BEFORE_ZC[$g]=$(get_zc)

  curl -s -X POST --max-time 180 --data-binary @/tmp/$g.influx 'http://localhost:8428/write' \
    -o /dev/null -w "  写入 HTTP: %{http_code}\n"
  curl -s -X POST --max-time 30 'http://localhost:8428/internal/force_flush' -o /dev/null
  sleep 8

  AFTER_TS[$g]=$(get_ts); AFTER_VAL[$g]=$(get_val)
  AFTER_ZO[$g]=$(get_zo); AFTER_ZC[$g]=$(get_zc)

  echo "  timestamps 增量: $(( AFTER_TS[$g] - BEFORE_TS[$g] )) 字节"
  echo "  values     增量: $(( AFTER_VAL[$g] - BEFORE_VAL[$g] )) 字节"
  echo "  ZSTD 原始增量  : $(( AFTER_ZO[$g] - BEFORE_ZO[$g] )) 字节"
  echo "  ZSTD 压缩增量  : $(( AFTER_ZC[$g] - BEFORE_ZC[$g] )) 字节"
  ZO=$(( AFTER_ZO[$g] - BEFORE_ZO[$g] )); ZC=$(( AFTER_ZC[$g] - BEFORE_ZC[$g] ))
  if [ "$ZC" -gt 0 ]; then
    echo "  → 压缩比: $(echo "scale=3;$ZO/$ZC"|bc) 倍"
  fi
done

echo
echo "=============================================="
echo " 验证全部可查（这次时间戳在过去）"
echo "=============================================="
for m in l06r_const_value l06r_slow_value l06r_random_value; do
  C=$(Q "count($m)" | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
  N=$(Q "count_over_time($m[30m])" | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(sum(float(r["value"][1]) for r in d)))' 2>/dev/null)
  echo "  $m : $C 条序列 / $N 个样本"
done

echo
echo "=============================================="
echo " 理论对照"
echo "=============================================="
echo "  每组 40000 样本 × 16 字节 = 640000 字节 (0.61 MB)"
