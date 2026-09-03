#!/usr/bin/env bash
# 课 5 疑点排查：写入 200 条全新序列，为什么 new_timeseries_created 不涨？
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW=$(date +%s)

echo "########## 疑点：items_added 涨了 2000，但 new_timeseries 没涨 ##########"
echo "  可能原因："
echo "    A. 指标被 relabel 掉了（课 4 的 relabel.yaml 还在生效）"
echo "    B. new_timeseries_created_total 是 counter，但采样时机不对"
echo "    C. 序列其实已存在（之前写过）"
echo "    D. 指标语义与我理解的不同"
echo

echo "########## 验证 A：relabel 配置是否还在生效 ##########"
echo "  --- 当前 relabel.yaml 内容 ---"
docker exec vm-learn cat /etc/victoriametrics/relabel.yaml 2>&1 | sed 's/^/    /'
echo
echo "  --- 检查写入的序列实际是否落库 ---"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l05_tsid_brandnew"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d[:3]: print("      ", m)
'

echo
echo "########## 验证 B：new_timeseries 到底涨没涨（精确采样）##########"
echo "  --- 用完全新的指标名，写入前后立刻对比 ---"
B=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total{job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "    写入前 = $B"

python3 - "$NOW" <<'PY' > /tmp/l05_probe2.txt
import sys
now=int(sys.argv[1])
for i in range(50):
    print(f'l05_probe_unique_{now}{{seq="p{i}"}} {i} {now}')
PY
echo "    写入 50 条全新序列（指标名含时间戳，保证唯一）"
curl -s -m 60 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_probe2.txt
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 3

A=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total{job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "    写入后 = $A"
echo "    增量 = $((A - B))"

echo
echo "########## 验证 C：序列是否真的落库了 ##########"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={__name__=~"l05_probe_unique.*"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条".format(len(d)))
for m in d[:3]: print("      ", m)
'

echo
echo "########## 验证 D：slow_row_inserts 是否同步增长 ##########"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_slow_row_inserts_total|vm_new_timeseries_created_total",job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
for it in r:
    print("      {:45s} = {}".format(it["metric"].get("__name__"), it["value"][1]))
'

echo
echo "########## 验证 E：items_added 涨 2000 的原因 ##########"
echo "  200 条序列 × 每条约 10 个索引条目 = 2000"
echo "  这与官方博客说的「一条序列产生约 10 个 indexDB 条目」吻合！"
echo "  验证：写入 1 条带 3 标签的序列，看增量"
B2=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary \
  "l05_one_series{a=\"1\",b=\"2\",c=\"3\"} 1 ${NOW}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
A2=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "    1 条序列(3标签) 的 items 增量 = $((A2 - B2))"

echo
echo "########## 验证 F：为什么 new_timeseries 不涨？检查是否是 self-scrape 干扰 ##########"
echo "  --- 不带 job 过滤，看所有 new_timeseries ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total' --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
for it in r:
    print("      {:60s} = {}".format(str({k:v for k,v in it["metric"].items() if k!="__name__"})[:60], it["value"][1]))
'
