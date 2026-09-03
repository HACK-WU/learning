#!/usr/bin/env bash
# 课 5 步骤 2：深入 part 目录内部 + indexdb 结构
set -u
DATA=/mnt/d/projects/learning/victoriametrics/playground/data
PARTITION="$DATA/data/small/2026_09"
IDX="$DATA/data/indexdb"

echo "########## 1. 单个 data part 目录内部的文件 ##########"
# 用 find 精确定位第一个真正的 part 目录（含 metadata.json）
PART=$(find "$PARTITION" -mindepth 1 -maxdepth 1 -type d ! -name snapshots | sort | head -1)
echo "  part: $(basename "$PART")"
ls -la "$PART/" | sed 's/^/  /'
echo
echo "  --- metadata.json ---"
cat "$PART/metadata.json" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/  /'

echo
echo "########## 2. 所有 part 的 metadata 汇总（看合并过程）##########"
printf '  %-20s %-10s %-8s %-14s %-14s\n' "PART" "ROWS" "BLOCKS" "MIN_TS" "MAX_TS"
echo "  ----------------------------------------------------------------------"
for p in $(find "$PARTITION" -mindepth 1 -maxdepth 1 -type d ! -name snapshots | sort); do
  if [ -f "$p/metadata.json" ]; then
    python3 -c "
import json,sys,os
d=json.load(open('$p/metadata.json'))
print('  %-20s %-10s %-8s %-14s %-14s' % (
    os.path.basename('$p'),
    d.get('RowsCount','-'), d.get('BlocksCount','-'),
    d.get('MinTimestamp','-'), d.get('MaxTimestamp','-')))
"
  fi
done

echo
echo "########## 3. indexdb 目录结构 ##########"
echo "  --- indexdb/ 顶层 ---"
ls -la "$IDX/" | sed 's/^/  /'
echo
echo "  --- indexdb 下各 table 目录 ---"
for t in $(find "$IDX" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | sort); do
  echo "  table: $(basename "$t")"
  find "$t" -maxdepth 1 | sed 's/^/    /'
done

echo
echo "########## 4. indexdb part 内部文件 ##########"
for t in $(find "$IDX" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | sort); do
  IP=$(find "$t" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | sort | head -1)
  if [ -n "$IP" ] && [ -f "$IP/metadata.json" ]; then
    echo "  --- table $(basename "$t") / part $(basename "$IP") ---"
    ls -la "$IP/" | sed 's/^/    /'
    echo "    metadata.json:"
    cat "$IP/metadata.json" | python3 -m json.tool 2>/dev/null | sed 's/^/      /'
    break
  fi
done

echo
echo "########## 5. indexdb 各 table 的 parts.json ##########"
for t in $(find "$IDX" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | sort | head -4); do
  if [ -f "$t/parts.json" ]; then
    echo "  --- table $(basename "$t") ---"
    cat "$t/parts.json" | python3 -c '
import sys,json
d=json.load(sys.stdin)
for k,v in d.items():
    print("      {}: {} 个 part".format(k, len(v) if v else 0))
' 2>/dev/null
  fi
done

echo
echo "########## 6. data/big 分区情况（big 目前是否为空）##########"
BP="$DATA/data/big/2026_09"
echo "  big/2026_09 下的 part 数: $(find "$BP" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | wc -l)"
if [ -f "$BP/parts.json" ]; then
  cat "$BP/parts.json" | python3 -c '
import sys,json
d=json.load(sys.stdin)
print("    Small: {} 个, Big: {} 个".format(len(d.get("Small",[])), len(d.get("Big",[]))))
for p in d.get("Big",[])[:5]: print("      Big part:", p)
' 2>/dev/null
fi

echo
echo "########## 7. 文件类型统计（看哪些文件最占空间）##########"
echo "  --- data/ 下各文件名出现次数 ---"
find "$DATA/data" -type f -name "*.bin" -o -type f -name "*.json" 2>/dev/null \
  | sed 's#.*/##' | sort | uniq -c | sort -rn | sed 's/^/  /'

echo
echo "  --- 各类型文件总大小 ---"
for f in timestamps.bin values.bin index.bin metaindex.bin items.bin lens.bin metadata.json parts.json; do
  sz=$(find "$DATA/data" -type f -name "$f" -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1)
  cnt=$(find "$DATA/data" -type f -name "$f" 2>/dev/null | wc -l)
  [ "$cnt" -gt 0 ] && printf '  %-16s %6s 个  %10s 字节\n' "$f" "$cnt" "${sz:-0}"
done
