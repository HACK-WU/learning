#!/bin/bash
# 课 6 核心测量：逻辑原始大小 vs 磁盘真实占用 = 端到端压缩率
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

echo "=============================================="
echo " C1 磁盘真实占用（分类型）"
echo "=============================================="
for t in timestamps.bin values.bin index.bin metaindex.bin items.bin lens.bin; do
  b=$(find data -name "$t" -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
  printf "  %-16s %10d 字节\n" "$t" "$b"
done
echo "  ----------------------------------------"
TOTAL=$(find data -type f -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
printf "  %-16s %10d 字节 (%.3f MB)\n" "data/ 合计" "$TOTAL" "$(echo "scale=6;$TOTAL/1048576"|bc 2>/dev/null || echo 0)"

echo
echo "=============================================="
echo " C2 逻辑原始大小估算"
echo "=============================================="
echo "  思路：磁盘上的数据 = 时间戳列 + 值列"
echo "  若用朴素行式存储（每行存一个 float64 值 + 一个 int64 时间戳）："
echo "    每行 = 8 + 8 = 16 字节"
echo
ROWS=$(curl -s --max-time 10 --data-urlencode 'query=sum(vm_rows{type="storage/small"})' http://localhost:8428/api/v1/query \
  | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]["result"]; print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
echo "  当前 storage/small 样本行数: $ROWS"
if [ "$ROWS" -gt 0 ]; then
  RAW=$((ROWS * 16))
  echo "  朴素行式存储需要: $RAW 字节 ($(echo "scale=3;$RAW/1048576"|bc) MB)"
  echo "  磁盘实际(ts+values): $(( $(find data -name 'timestamps.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}') + $(find data -name 'values.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}') )) 字节"
  TS=$(find data -name 'timestamps.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
  VAL=$(find data -name 'values.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
  TV=$((TS+VAL))
  echo "  → 纯数据压缩比: $(echo "scale=3;$RAW/$TV"|bc) 倍 (省 $(echo "scale=1;(1-$TV/$RAW)*100"|bc)%)"
fi

echo
echo "=============================================="
echo " C3 逐 part 明细：看每块压缩了多少行"
echo "=============================================="
printf "%-46s %10s %10s %10s %8s\n" "PART" "timestamps" "values" "合计" "行数"
printf "%-46s %10s %10s %10s %8s\n" "----" "----------" "------" "----" "----"
for p in $(find data/data/small -mindepth 2 -maxdepth 2 -type d 2>/dev/null); do
  ts=$(stat -c %s "$p/timestamps.bin" 2>/dev/null || echo 0)
  vl=$(stat -c %s "$p/values.bin" 2>/dev/null || echo 0)
  # 从 metadata.json 读行数
  rows=$(python3 -c "
import json,sys
try:
    d=json.load(open('$p/metadata.json'))
    print(d.get('rows_count', d.get('rowsCount', '?')))
except: print('?')
" 2>/dev/null)
  printf "%-46s %10d %10d %10d %8s\n" "$(basename $p)" "$ts" "$vl" "$((ts+vl))" "$rows"
done

echo
echo "=============================================="
echo " C4 平均每条样本占多少字节（核心指标！）"
echo "=============================================="
if [ "$ROWS" -gt 0 ]; then
  TS=$(find data -name 'timestamps.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
  VAL=$(find data -name 'values.bin' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
  ALL=$(find data -type f -printf '%s\n' | awk '{s+=$1} END {print s+0}')
  echo "  仅数据列(ts+values) : $(echo "scale=4;($TS+$VAL)/$ROWS"|bc) 字节/样本"
  echo "  含索引(data全量)    : $(echo "scale=4;$ALL/$ROWS"|bc) 字节/样本"
  echo "  朴素行式            : 16.0000 字节/样本"
fi

echo
echo "=============================================="
echo " C5 验证 ZSTD magic number（28 b5 2f fd）"
echo "=============================================="
for p in $(find data/data/small -mindepth 2 -maxdepth 2 -type d 2>/dev/null | head -3); do
  for f in timestamps.bin values.bin; do
    [ -f "$p/$f" ] || continue
    magic=$(od -A n -t x1 -N 4 "$p/$f" | tr -d ' \n')
    if [ "$magic" = "28b52ffd" ]; then
      echo "  [ZSTD]  $(basename $p)/$f  magic=$magic"
    else
      echo "  [OTHER] $(basename $p)/$f  magic=$magic"
    fi
  done
done
