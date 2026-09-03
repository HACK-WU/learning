#!/usr/bin/env bash
# 课 5 步骤 4：TSID 与 indexDB 实测
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW=$(date +%s)

echo "########## 1. TSID 缓存命中 vs 未命中（slow inserts）##########"
echo "  关键指标："
echo "    vm_slow_row_inserts_total      —— 走慢路径的行数（TSID 缓存未命中）"
echo "    vm_new_timeseries_created_total —— 全新创建的序列数"
echo
echo "  --- 写入前的基线 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_slow_row_inserts_total' --data-urlencode "nocache=1" \
| python3 "$FMT" | sed -n '2,3p'
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total' --data-urlencode "nocache=1" \
| python3 "$FMT" | sed -n '2,3p'

echo
echo "########## 2. 写入【全新】序列 → 应触发 slow insert + new timeseries ##########"
python3 - "$NOW" <<'PY' > /tmp/l05_new.txt
import sys
now=int(sys.argv[1])
# 200 条全新序列
for i in range(200):
    print(f'l05_tsid_brandnew{{idx="n{i}"}} {i} {now}')
PY
echo "  写入 200 条全新序列"
curl -s -m 60 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_new.txt
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "  --- 写入后 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total' --data-urlencode "nocache=1" \
| python3 "$FMT" | sed -n '2,3p'

echo
echo "########## 3. 重复写入【同一批】序列 → 应命中缓存，slow insert 不再涨 ##########"
echo "  重复写入同样 200 条（同样的 metric + labels）"
for i in 1 2 3 4 5; do
  curl -s -m 60 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_new.txt
done
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
echo "  --- 重复写入后 new_timeseries 应不再增长 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=vm_new_timeseries_created_total' --data-urlencode "nocache=1" \
| python3 "$FMT" | sed -n '2,3p'

echo
echo "########## 4. indexDB 条目添加统计 ##########"
echo "    vm_indexdb_items_added_total       —— 添加到 indexDB 的条目数"
echo "    vm_indexdb_items_added_size_bytes_total —— 这些条目占的字节数"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_indexdb_items_added.*"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
for it in r[:8]:
    print("      {:55s} = {}".format(it["metric"].get("__name__"), it["value"][1]))
'

echo
echo "########## 5. 验证倒排索引：一条序列在 indexDB 里产生多少条目 ##########"
echo "  理论：1 条带 N 个标签的序列，在 indexDB 中产生多条映射"
echo "  （metric名 + 每个label名 + 每个label名值对 + 组合索引 + global/per-day 两份）"
echo
echo "  --- 写入 1 条带 3 个标签的序列，观察 items 增量 ---"
BEFORE=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "    写入前 items_added_total = $BEFORE"

curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary \
  "l05_idx_probe{region=\"us-east\",env=\"prod\",svc=\"api\"} 42 ${NOW}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
sleep 2
AFTER=$(curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query=sum(vm_indexdb_items_added_total)' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)')
echo "    写入后 items_added_total = $AFTER"
echo "    增量 = $((AFTER - BEFORE)) 条（1 条序列 + 3 个标签产生的索引条目）"

echo
echo "########## 6. TSID 缓存相关配置 ##########"
echo "  --- vm_tsid_cache 相关指标 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_tsid.*|vm_cache_.*"}' \
  --data-urlencode "nocache=1" \
| python3 -c '
import sys,json
r=json.load(sys.stdin)["data"]["result"]
if not r: print("      (无相关指标)")
for it in r[:14]:
    print("      {:52s} = {}".format(it["metric"].get("__name__"), it["value"][1]))
'

echo
echo "########## 7. 查询路径：per-day index vs global index ##########"
echo "  官方规则：查询时间范围 ≤ 40 天用 per-day index，> 40 天用 global index"
echo
echo "  --- 短范围查询（≤40天）---"
curl -s -m 20 -G "$VM/api/v1/query_range" \
  --data-urlencode 'query=l05_idx_probe' \
  --data-urlencode "start=$((NOW-3600))" --data-urlencode "end=$NOW" \
  --data-urlencode 'step=60' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;d=json.load(sys.stdin);r=d["data"]["result"];print("      命中 {} 条序列".format(len(r)))'
echo "  --- 长范围查询（>40天）---"
curl -s -m 20 -G "$VM/api/v1/query_range" \
  --data-urlencode 'query=l05_idx_probe' \
  --data-urlencode "start=$((NOW-60*86400))" --data-urlencode "end=$NOW" \
  --data-urlencode 'step=3600' --data-urlencode "nocache=1" \
| python3 -c 'import sys,json;d=json.load(sys.stdin);r=d["data"]["result"];print("      命中 {} 条序列".format(len(r)))'
