#!/usr/bin/env bash
# 课 5 疑点终结：分离变量 —— 全新指标名 vs 已有指标名新标签值
set -u
VM=http://localhost:8428
NOW=$(date +%s)

q1() {
  curl -s -m 15 -G "$VM/api/v1/query" \
    --data-urlencode "query=$1{job=\"victoria-metrics\"}" \
    --data-urlencode "nocache=1" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)'
}
qsum() {
  curl -s -m 15 -G "$VM/api/v1/query" \
    --data-urlencode "query=$1" --data-urlencode "nocache=1" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print(r[0]["value"][1] if r else 0)'
}

echo "########## 对照实验设计 ##########"
echo "  场景 A：全新【指标名】（此前从未出现过）"
echo "  场景 B：已有指标名 + 全新【标签值】"
echo "  观察 new_timeseries / slow_inserts / items_added 三个指标的变化"
echo

echo "########## 场景 A：全新指标名（1 条）##########"
B_NT=$(q1 vm_new_timeseries_created_total); B_SI=$(q1 vm_slow_row_inserts_total); B_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" \
  --data-binary "l05_caseA_${NOW}{tag=\"v1\"} 1 ${NOW}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"; sleep 3
A_NT=$(q1 vm_new_timeseries_created_total); A_SI=$(q1 vm_slow_row_inserts_total); A_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
echo "  new_timeseries: $B_NT → $A_NT  (增量 $((A_NT-B_NT)))"
echo "  slow_inserts  : $B_SI → $A_SI  (增量 $((A_SI-B_SI)))"
echo "  items_added   : $B_IT → $A_IT  (增量 $((A_IT-B_IT)))"

echo
echo "########## 场景 B：同指标名 + 全新标签值（20 条）##########"
B_NT=$(q1 vm_new_timeseries_created_total); B_SI=$(q1 vm_slow_row_inserts_total); B_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
python3 - "$NOW" <<'PY' > /tmp/l05_caseB.txt
import sys
now=int(sys.argv[1])
for i in range(20):
    print(f'l05_caseB_{now}{{tag="v{i}"}} {i} {now}')
PY
curl -s -m 30 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_caseB.txt
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"; sleep 3
A_NT=$(q1 vm_new_timeseries_created_total); A_SI=$(q1 vm_slow_row_inserts_total); A_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
echo "  new_timeseries: $B_NT → $A_NT  (增量 $((A_NT-B_NT)))  ← 20 条新序列"
echo "  slow_inserts  : $B_SI → $A_SI  (增量 $((A_SI-B_SI)))"
echo "  items_added   : $B_IT → $A_IT  (增量 $((A_IT-B_IT)))"

echo
echo "########## 场景 C：重复写入场景 B 的 20 条（索引应已建立）##########"
B_NT=$(q1 vm_new_timeseries_created_total); B_SI=$(q1 vm_slow_row_inserts_total); B_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
for i in 1 2 3; do
  curl -s -m 30 -o /dev/null -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l05_caseB.txt
done
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"; sleep 3
A_NT=$(q1 vm_new_timeseries_created_total); A_SI=$(q1 vm_slow_row_inserts_total); A_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
echo "  new_timeseries: 增量 $((A_NT-B_NT))  ← 应为 0（序列已存在）"
echo "  slow_inserts  : 增量 $((A_SI-B_SI))"
echo "  items_added   : 增量 $((A_IT-B_IT))  ← 索引已建，应接近 0"

echo
echo "########## 关键：确认 cache 目录（日志里看到的）##########"
echo "  --- 数据目录下的 cache 目录 ---"
docker exec vm-learn ls -la /victoria-metrics-data/cache/ 2>&1 | sed 's/^/    /'
echo
echo "  --- VM 日志中的 cache 创建记录 ---"
docker logs vm-learn 2>&1 | grep -E 'creating new cache' | tail -8 | sed 's/^/    /'

echo
echo "########## 结论验证：为什么单条写入 items 增量为 0？##########"
echo "  假设：items_added 只在【in-memory part 落盘为磁盘 part】时才增加，"
echo "        force_flush 后需要等待索引落盘，采样太快看不到。"
echo
echo "  验证：写入后等 10 秒再采样"
B_IT=$(qsum 'sum(vm_indexdb_items_added_total)')
curl -s -m 15 -o /dev/null -X POST "$VM/api/v1/import/prometheus" \
  --data-binary "l05_delay_${NOW}{a=\"1\",b=\"2\"} 1 ${NOW}"
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"
echo "    force_flush 后立即: 增量 $(( $(qsum 'sum(vm_indexdb_items_added_total)') - B_IT ))"
sleep 10
curl -s -m 30 -o /dev/null "$VM/internal/force_flush"; sleep 2
echo "    等待 10 秒后:       增量 $(( $(qsum 'sum(vm_indexdb_items_added_total)') - B_IT ))"
