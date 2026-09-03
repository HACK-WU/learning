#!/usr/bin/env bash
# 流式聚合最终验证：写入数据后等待一个完整聚合窗口，观察 flush 与输出
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py

echo "########## 1. 记录当前 flush 次数（基线）##########"
BASE=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_streamaggr_flush_duration_seconds_count)' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "  当前 flush 累计次数: $BASE"

echo
echo "########## 2. 写入 l04_highcard 数据（走 native import）##########"
NOW=$(date +%s)
python3 - "$NOW" <<'PY' > /tmp/l04_sa2.txt
import sys
now=int(sys.argv[1])
for i in range(50):
    print(f'l04_highcard{{user_id="sa{i}",endpoint="/api/order"}} {i} {now}')
PY
echo "  写入 $(grep -c . /tmp/l04_sa2.txt) 行"
curl -s -m 60 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l04_sa2.txt
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"

echo
echo "########## 3. 等一个完整聚合窗口（1m）+ 缓冲 ##########"
echo "  等待 75 秒，跨过至少一个 flush 边界..."
sleep 75
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"
sleep 3

echo
echo "########## 4. 对比 flush 次数变化 ##########"
AFTER=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_streamaggr_flush_duration_seconds_count)' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "  基线: $BASE → 现在: $AFTER （增量: $((AFTER - BASE))）"

echo
echo "########## 5. 查聚合输出指标 ##########"
echo "  --- 所有带 : 的聚合输出指标名 ---"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~".+:1m.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    聚合输出 {} 条：".format(len(d)))
for m in d[:10]: print("      ", m)
'

echo
echo "  --- 精确查 l04_highcard 的聚合输出 ---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"l04_highcard.*"}' \
  --data-urlencode "nocache=1" | python3 "$FMT"

echo
echo "########## 6. 检查 l04_highcard 原始数据是否还在 ##########"
echo "  -streamAggr.keepInput 默认 false → 匹配的原始样本应被丢弃"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count(l04_highcard)' \
  --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,3p'

echo
echo "########## 7. 检查 streamAggr 样本计数 ##########"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_streamaggr_(input|output|matched|ignored|dedup).*"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
seen={}
for it in r:
    n=it["metric"].get("__name__")
    if "count" in n or "sum" in n or "_total" in n:
        seen[n]=it["value"][1]
for k in sorted(seen): print("      {:60s} {}".format(k, seen[k]))
'
