#!/usr/bin/env bash
# 课 5 步骤 3：实测后台合并——观察 small part 合并、以及 small → big 的迁移
set -u
VM=http://localhost:8428
DATA=/mnt/d/projects/learning/victoriametrics/playground/data
PARTITION="$DATA/data/small/2026_09"
BIG="$DATA/data/big/2026_09"

count_parts() { find "$1" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | wc -l; }

echo "########## 1. 合并前的状态 ##########"
echo "  small/2026_09 part 数: $(count_parts "$PARTITION")"
echo "  big/2026_09   part 数: $(count_parts "$BIG")"
echo "  总 series: $(curl -s -m 10 "$VM/api/v1/series/count")"

echo
echo "########## 2. 批量写入数据，制造大量小 part ##########"
echo "  分批写入，每批后 force_flush，产生独立 part"
NOW=$(date +%s)
for i in $(seq 1 12); do
  python3 - "$NOW" "$i" <<'PY' > /tmp/l05_batch.txt
import sys
now=int(sys.argv[1]); b=int(sys.argv[2])
for j in range(500):
    print(f'l05_merge_test{{batch="{b}",idx="{j}"}} {j*1.5} {now + b*10}')
PY
  curl -s -m 60 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_batch.txt
  curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
  printf "    第 %2d 批写入完成\n" "$i"
  sleep 1
done

echo
echo "########## 3. 写入后（合并前）的 part 数 ##########"
echo "  small/2026_09 part 数: $(count_parts "$PARTITION")"
echo "  big/2026_09   part 数: $(count_parts "$BIG")"

echo
echo "########## 4. 当前的 part 清单（按时间排序，看小 part 堆积）##########"
for p in $(find "$PARTITION" -mindepth 1 -maxdepth 1 -type d ! -name snapshots | sort); do
  if [ -f "$p/metadata.json" ]; then
    python3 -c "
import json,os
d=json.load(open('$p/metadata.json'))
sz=sum(os.path.getsize(os.path.join('$p',f)) for f in os.listdir('$p'))
print('    %-20s rows=%-8s blocks=%-6s size=%s B' % (os.path.basename('$p'), d.get('RowsCount','-'), d.get('BlocksCount','-'), sz))
"
  fi
done | tail -18

echo
echo "########## 5. 观察合并过程（等 60 秒，每秒采样 part 数）##########"
echo "  VM 后台合并由 -mergeSmallPartsInterval 控制，查看当前值："
curl -s -m 10 "$VM/flags" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for k in ['mergeSmallPartsInterval','inmemoryDataFlushInterval','finalMergeDelay','retentionPeriod']:
        if k in d: print('    {}: {}'.format(k, d[k]))
except Exception as e:
    print('    (无法读取 flags: {})'.format(e))
"

echo
echo "  开始采样（part 数应随合并而减少）:"
for i in $(seq 1 12); do
  s=$(count_parts "$PARTITION"); b=$(count_parts "$BIG")
  printf '    t=%-3ss  small=%-3s  big=%-3s\n' "$((i*5))" "$s" "$b"
  sleep 5
done

echo
echo "########## 6. 合并后的 part 清单 ##########"
for p in $(find "$PARTITION" -mindepth 1 -maxdepth 1 -type d ! -name snapshots | sort); do
  if [ -f "$p/metadata.json" ]; then
    python3 -c "
import json,os
d=json.load(open('$p/metadata.json'))
sz=sum(os.path.getsize(os.path.join('$p',f)) for f in os.listdir('$p'))
print('    %-20s rows=%-8s blocks=%-6s size=%s B' % (os.path.basename('$p'), d.get('RowsCount','-'), d.get('BlocksCount','-'), sz))
"
  fi
done | tail -12

echo
echo "########## 7. 合并相关的 VM 自监控指标 ##########"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_merge_.*|vm_parts_.*|vm_assisted_merges_.*"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("    命中 {} 条".format(len(r)))
for it in r[:20]:
    n=it["metric"].get("__name__")
    labs={k:v for k,v in it["metric"].items() if k!="__name__"}
    print("      {:55s} {:25s} = {}".format(n, str(labs)[:25], it["value"][1]))
'
