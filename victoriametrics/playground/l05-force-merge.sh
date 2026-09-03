#!/usr/bin/env bash
# 课 5 步骤 5：强制触发 big part —— 观察 small → big 的完整迁移链路
set -u
VM=http://localhost:8428
DATA=/mnt/d/projects/learning/victoriametrics/playground/data
PARTITION="$DATA/data/small/2026_09"
BIG="$DATA/data/big/2026_09"

count_parts() { find "$1" -mindepth 1 -maxdepth 1 -type d ! -name snapshots 2>/dev/null | wc -l; }

echo "########## 1. 迁移前状态 ##########"
echo "  small part 数: $(count_parts "$PARTITION")"
echo "  big   part 数: $(count_parts "$BIG")"
echo "  small 目录大小: $(du -sh "$PARTITION" 2>/dev/null | cut -f1)"
echo "  big   目录大小: $(du -sh "$BIG" 2>/dev/null | cut -f1)"

echo
echo "########## 2. 写入大量数据，让 small part 长大 ##########"
echo "  写入 5 万条样本，制造足够大的 small part"
NOW=$(date +%s)
python3 - "$NOW" <<'PY' > /tmp/l05_bigload.txt
import sys
now=int(sys.argv[1])
lines=[]
# 200 个序列 × 250 个时间点 = 50000 样本
for s in range(200):
    for t in range(250):
        lines.append(f'l05_bigload{{series="s{s}"}} {s+t*0.1} {now - (250-t)*60}')
print("\n".join(lines))
PY
echo "  样本数: $(grep -c . /tmp/l05_bigload.txt)"
curl -s -m 180 -o /dev/null -w "    写入 http=%{http_code}\n" \
  -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_bigload.txt
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"
sleep 5
echo "  写入后: small=$(count_parts "$PARTITION")  big=$(count_parts "$BIG")"

echo
echo "########## 3. 强制合并：/internal/force_merge ##########"
echo "  端点: POST /internal/force_merge?partition_prefix=YYYY_MM"
echo "  作用：强制把 small part 合并为 big part"
curl -s -m 300 -o /dev/null -w "    force_merge http=%{http_code}\n" \
  -X POST "$VM/internal/force_merge?partition_prefix=2026_09"

echo
echo "  等待合并完成（60 秒）..."
for i in $(seq 1 12); do
  printf '    t=%-3ss  small=%-3s  big=%-3s\n' "$((i*5))" "$(count_parts "$PARTITION")" "$(count_parts "$BIG")"
  sleep 5
done

echo
echo "########## 4. 迁移后的 part 清单对比 ##########"
echo "  --- small 分区（应减少）---"
for p in $(find "$PARTITION" -mindepth 1 -maxdepth 1 -type d ! -name snapshots | sort | tail -6); do
  [ -f "$p/metadata.json" ] && python3 -c "
import json,os
d=json.load(open('$p/metadata.json'))
sz=sum(os.path.getsize(os.path.join('$p',f)) for f in os.listdir('$p'))
print('    small/{}  rows={}  size={} B'.format(os.path.basename('$p'), d.get('RowsCount','-'), sz))
"
done

echo
echo "  --- big 分区（应出现）---"
for p in $(find "$BIG" -mindepth 1 -maxdepth 1 -type d ! -name snapshots | sort); do
  [ -f "$p/metadata.json" ] && python3 -c "
import json,os
d=json.load(open('$p/metadata.json'))
sz=sum(os.path.getsize(os.path.join('$p',f)) for f in os.listdir('$p'))
print('    big/{}  rows={}  blocks={}  size={} B'.format(os.path.basename('$p'), d.get('RowsCount','-'), d.get('BlocksCount','-'), sz))
"
done
[ "$(count_parts "$BIG")" = "0" ] && echo "    (big 分区仍为空 —— 数据量或时间未达阈值)"

echo
echo "########## 5. 目录大小变化 ##########"
echo "  small: $(du -sh "$PARTITION" 2>/dev/null | cut -f1)"
echo "  big  : $(du -sh "$BIG" 2>/dev/null | cut -f1)"

echo
echo "########## 6. 验证数据完整性（迁移后数据应仍可查）##########"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count(l05_bigload)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    l05_bigload 序列数:", r[0]["value"][1] if r else 0)'

echo
echo "########## 7. 合并统计指标 ##########"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_(merge|rows|data_size).*"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
seen=set()
for it in r:
    n=it["metric"].get("__name__")
    labs={k:v for k,v in it["metric"].items() if k!="__name__" and k!="__name__"}
    key=(n, tuple(sorted(labs.items())))
    if key in seen: continue
    seen.add(key)
    print("    {:48s} {:30s} = {}".format(n, str(labs)[:30], it["value"][1]))
' 2>/dev/null | head -20
