#!/usr/bin/env bash
# 课 5 疑点终结 v4：验证 new_timeseries 增长是否来自 self-scrape 的干扰
set -u
VM=http://localhost:8428

echo "########## 假设：self-scrape 每 10s 写入 VM 自身指标，"
echo "          其中包含大量高 churn 序列（如 vm_http_request_duration_seconds_bucket）"
echo "          这些持续产生 new_timeseries，掩盖了我们的测量信号"
echo

echo "########## 验证 1：静默 30 秒（不写入任何数据），看 new_timeseries 是否自己涨 ##########"
q1() {
  curl -s -m 15 -G "$VM/api/v1/query" \
    --data-urlencode "query=$1{job=\"victoria-metrics\"}" --data-urlencode "nocache=1" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)'
}
B=$(q1 vm_new_timeseries_created_total)
BS=$(q1 vm_slow_row_inserts_total)
echo "  静默前: new_timeseries=$B  slow_inserts=$BS"
echo "  静默 30 秒（期间不写入任何数据，只有 self-scrape 在跑）..."
sleep 30
A=$(q1 vm_new_timeseries_created_total)
AS=$(q1 vm_slow_row_inserts_total)
echo "  静默后: new_timeseries=$A  slow_inserts=$AS"
echo "  ★ 静默期增量: new_timeseries=$((A-B))  slow_inserts=$((AS-BS))"
echo "    （若 >0，证明增长来自 self-scrape 而非我们的写入）"

echo
echo "########## 验证 2：看 self-scrape 到底写了多少序列 ##########"
echo "  --- vm_http_request_duration_seconds_bucket 的序列数（高 churn）---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=count({__name__=~"vm_http_request_duration_seconds_bucket"})' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    序列数:", r[0]["value"][1] if r else 0)'

echo "  --- le 标签的唯一值数（每个 bucket 都是一条序列）---"
curl -s -m 20 -G "$VM/api/v1/labels" --data-urlencode 'match[]={__name__=~".*"}' 2>/dev/null \
| python3 -c 'import sys,json;d=json.load(sys.stdin)["data"];print("    标签名数:", len(d))' 2>/dev/null

echo
echo "########## 验证 3：用 increase() 观察 churn rate（官方推荐用法）##########"
echo "  官方推荐: increase(vm_new_timeseries_created_total[1h]) = churn rate"
echo
echo "  --- 最近 5 分钟的 churn rate ---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(increase(vm_new_timeseries_created_total[5m]))' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    5分钟新增序列数:", r[0]["value"][1] if r else 0)'
echo "  --- 最近 5 分钟的 slow inserts ---"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(increase(vm_slow_row_inserts_total[5m]))' \
  --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("    5分钟慢插入数:", r[0]["value"][1] if r else 0)'

echo
echo "########## 验证 4：active time series（课 7 的重点，这里先看一眼）##########"
curl -s -m 20 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_cache_entries{type="storage/hour_metric_ids"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
print("    活跃序列数(最近1小时):", r[0]["value"][1] if r else "(无)")
'

echo
echo "########## 验证 5：items_added 的滞后性确认 ##########"
echo "  items_added 只在 indexDB 的 in-memory part 落盘时才计数"
echo "  实测：force_flush 后立即 vs 等待后"
qsum() {
  curl -s -m 15 -G "$VM/api/v1/query" \
    --data-urlencode "query=sum($1)" --data-urlencode "nocache=1" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)'
}
NOW=$(date +%s)
B_IT=$(qsum 'vm_indexdb_items_added_total')
curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" \
  --data-binary "l05_lag_${NOW}{x=\"1\"} 1 ${NOW}"
echo "    [t=0]   写入后未 flush: 增量 $(( $(qsum 'vm_indexdb_items_added_total') - B_IT ))"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
echo "    [t=0]   force_flush 后: 增量 $(( $(qsum 'vm_indexdb_items_added_total') - B_IT ))"
sleep 8
echo "    [t=8s]  等待 8 秒后:    增量 $(( $(qsum 'vm_indexdb_items_added_total') - B_IT ))"
sleep 8
echo "    [t=16s] 等待 16 秒后:   增量 $(( $(qsum 'vm_indexdb_items_added_total') - B_IT ))"
