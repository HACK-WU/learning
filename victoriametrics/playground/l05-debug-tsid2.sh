#!/usr/bin/env bash
# 深挖：new_timeseries_created 的语义到底是什么
set -u
VM=http://localhost:8428
NOW=$(date +%s)

echo "########## 假设：new_timeseries 统计的是【慢路径】中新创建的 ##########"
echo "  官方博客原文："
echo "    vm_slow_row_inserts_total: rows that go through the slow ingestion path"
echo "    vm_new_timeseries_created_total: rows not found in both TSID cache and"
echo "                                     IndexDB, so a new TSID is created"
echo
echo "  按此定义，写入 200 条全新序列应该涨 200。实测只涨 4。"
echo
echo "  新假设：VM 有【TSID 预创建 / 批量预热机制】，"
echo "  或者 new_timeseries 只在【per-day index 首次见到】时才 +1。"
echo

echo "########## 验证 1：一次写入 1 条全新序列（最干净的实验）##########"
B=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total{job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
S_B=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_slow_row_inserts_total{job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "  写入前: new_timeseries=$B  slow_inserts=$S_B"

curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary \
  "l05_single_${NOW}{tag=\"only\"} 1 ${NOW}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 3

A=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total{job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
S_A=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_slow_row_inserts_total{job="victoria-metrics"}' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "  写入后: new_timeseries=$A  slow_inserts=$S_A"
echo "  增量:   new_timeseries=$((A-B))  slow_inserts=$((S_A-S_B))"

echo
echo "########## 验证 2：该序列是否落库 ##########"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode "match[]=l05_single_${NOW}" \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    落库 {} 条: {}".format(len(d), d))
'

echo
echo "########## 验证 3：items_added 是否随单条序列增长 ##########"
B3=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary \
  "l05_items_${NOW}{a=\"1\",b=\"2\",c=\"3\",d=\"4\"} 1 ${NOW}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 3
A3=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "  1 条序列(4标签) 的 items 增量 = $((A3 - B3))"

echo
echo "########## 验证 4：多次写入同一条新序列，items 是否重复增长 ##########"
B4=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary \
    "l05_items_${NOW}{a=\"1\",b=\"2\",c=\"3\",d=\"4\"} $i ${NOW}"
done
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 3
A4=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "  重复写入 10 次的 items 增量 = $((A4 - B4))  （若索引已建立，应接近 0）"

echo
echo "########## 验证 5：看 VM 日志里有没有相关线索 ##########"
docker logs vm-learn 2>&1 | grep -iE 'timeseries|tsid|precreat' | tail -8 | sed 's/^/    /'

echo
echo "########## 验证 6：vm_timeseries_precreated_total（官方提到的预热指标）##########"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_timeseries_precreated.*"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
if not r: print("    (该指标不存在)")
for it in r[:5]:
    print("      {:50s} = {}".format(it["metric"].get("__name__"), it["value"][1]))
'
