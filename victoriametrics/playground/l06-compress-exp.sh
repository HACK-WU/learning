#!/bin/bash
# 课 6 核心实验：三种数据形态的压缩率对照
# 控制变量：都是 1000 条序列 × 10 个时间点 = 10000 个样本
# 唯一变量：值的形态（恒定 / 缓慢变化 / 随机）
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }
NOW=$(date +%s)

echo "=============================================="
echo " 实验设计"
echo "=============================================="
echo "  三组数据，每组 1000 条序列 × 10 个时间点 = 10000 样本"
echo "  A 组 l06_a_const  : 值恒定 42.0           （最好压）"
echo "  B 组 l06_b_slow   : 值缓慢+1 递增          （中等）"
echo "  C 组 l06_c_random : 值完全随机 0-1000000   （最难压）"
echo
echo "  时间戳都是 10 秒等间隔（模拟真实采集）"

echo
echo "=============================================="
echo " 生成数据"
echo "=============================================="
python3 - <<PY
import random
random.seed(42)
now = $NOW
lines_a, lines_b, lines_c = [], [], []
for i in range(1000):
    for t in range(10):
        ts = (now + t*10) * 1000000000
        lines_a.append("l06_a_const,idx=%d value=42.0 %d" % (i, ts))
        lines_b.append("l06_b_slow,idx=%d value=%d.0 %d" % (i, 100+i+t, ts))
        lines_c.append("l06_c_random,idx=%d value=%d.0 %d" % (i, random.randint(0,1000000), ts))
for name, lines in [("l06_a_const", lines_a), ("l06_b_slow", lines_b), ("l06_c_random", lines_c)]:
    with open("/tmp/%s.influx" % name, "w") as f:
        f.write("\n".join(lines) + "\n")
    print("  %-14s %d 行" % (name, len(lines)))
PY

echo
echo "=============================================="
echo " 记录写入前基线"
echo "=============================================="
BEFORE_TS=$(find data -name 'timestamps.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
BEFORE_VAL=$(find data -name 'values.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
echo "  写前 timestamps.bin 合计: $BEFORE_TS 字节"
echo "  写前 values.bin     合计: $BEFORE_VAL 字节"

echo
echo "-- 记录写前 ZSTD 统计（这是最准的度量）--"
ZB_O=$(curl -s --max-time 15 --data-urlencode 'query=sum(vm_zstd_block_original_bytes_total)' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
ZB_C=$(curl -s --max-time 15 --data-urlencode 'query=sum(vm_zstd_block_compressed_bytes_total)' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
echo "  写前 ZSTD 原始: $ZB_O  /  压缩后: $ZB_C"

echo
echo "=============================================="
echo " 依次写入三组（每组之间强制 flush）"
echo "=============================================="
for g in l06_a_const l06_b_slow l06_c_random; do
  curl -s -X POST --max-time 120 --data-binary @/tmp/$g.influx 'http://localhost:8428/write' \
    -o /dev/null -w "  $g  HTTP: %{http_code}\n"
  sleep 2
  # 强制把内存中的数据刷到磁盘
  curl -s -X POST --max-time 30 'http://localhost:8428/internal/force_flush' -o /dev/null -w "    force_flush HTTP: %{http_code}\n" 2>&1
  sleep 3
done

echo
echo "=============================================="
echo " 写入后统计"
echo "=============================================="
sleep 5
AFTER_TS=$(find data -name 'timestamps.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
AFTER_VAL=$(find data -name 'values.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
echo "  写后 timestamps.bin 合计: $AFTER_TS 字节 (增量 $((AFTER_TS-BEFORE_TS)))"
echo "  写后 values.bin     合计: $AFTER_VAL 字节 (增量 $((AFTER_VAL-BEFORE_VAL)))"

ZA_O=$(curl -s --max-time 15 --data-urlencode 'query=sum(vm_zstd_block_original_bytes_total)' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
ZA_C=$(curl -s --max-time 15 --data-urlencode 'query=sum(vm_zstd_block_compressed_bytes_total)' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
echo "  写后 ZSTD 原始: $ZA_O  /  压缩后: $ZA_C"
echo "  本次实验 ZSTD 原始增量: $((ZA_O-ZB_O))  /  压缩后增量: $((ZA_C-ZB_C))"
if [ $((ZA_C-ZB_C)) -gt 0 ]; then
  echo "  → 本次写入的实际压缩比: $(echo "scale=3;($ZA_O-$ZB_O)/($ZA_C-$ZB_C)"|bc) 倍"
fi

echo
echo "=============================================="
echo " 验证三组都真的落盘了"
echo "=============================================="
for m in l06_a_const_value l06_b_slow_value l06_c_random_value; do
  R=$(Q "count($m)" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
  echo "  $m : $R 条序列"
done

echo
echo "=============================================="
echo " 理论对照：10000 样本的朴素大小"
echo "=============================================="
echo "  每组 10000 样本 × 16 字节(8时间戳+8值) = 160000 字节"
echo "  三组共 30000 样本 = 480000 字节 = $(echo "scale=2;480000/1048576"|bc) MB"
