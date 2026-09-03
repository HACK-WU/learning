#!/usr/bin/env bash
# 课 4 步骤 4：基数治理实测（制造基数爆炸 → cardinality explorer → relabel 丢弃 → 流式聚合）
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW=$(date +%s)

echo "########## 1. 制造基数爆炸：写入高基数标签 ##########"
echo "  模拟场景：误把 user_id / request_id 这类高基数字段做成标签"
python3 - "$NOW" <<'PY' > /tmp/l04_highcard.txt
import sys
now = int(sys.argv[1])
lines = []
# 5000 个不同 user_id → 5000 条序列
for i in range(5000):
    lines.append(f'l04_highcard{{user_id="u{i}",endpoint="/api/order"}} {i} {now}')
# 对比组：低基数
for i in range(5):
    lines.append(f'l04_lowcard{{region="r{i}",endpoint="/api/order"}} {i} {now}')
print("\n".join(lines))
PY
echo "  写入 $(grep -c . /tmp/l04_highcard.txt) 行（5000 高基数 + 5 低基数）"
curl -s -m 120 -o /dev/null -w "    http=%{http_code}\n" \
  -X POST "$VM/api/v1/import/prometheus" --data-binary @/tmp/l04_highcard.txt
curl -s -m 60 -o /dev/null "$VM/internal/force_flush"
sleep 3

echo
echo "########## 2. 用 /api/v1/status/tsdb 定位基数杀手 ##########"
echo "  cardinality explorer 就是基于这个端点"
curl -s -m 30 -G "$VM/api/v1/status/tsdb" \
  --data-urlencode 'topN=10' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
hd=d.get("headStats",{})
print("    headStats: numSeries={} numLabelPairs={} chunkCount={}".format(
    hd.get("numSeries"), hd.get("numLabelPairs"), hd.get("chunkCount")))
print()
print("    --- seriesCountByMetricName (Top 10) ---")
for m in (d.get("seriesCountByMetricName") or [])[:10]:
    print("      {:45s} {}".format(m["name"], m["value"]))
print()
print("    --- seriesCountByLabelName (Top 10) ---")
for m in (d.get("seriesCountByLabelName") or [])[:10]:
    print("      {:45s} {}".format(m["name"], m["value"]))
print()
print("    --- seriesCountByFocusLabelValue ---")
for m in (d.get("seriesCountByFocusLabelValue") or [])[:10]:
    print("      {:45s} {}".format(m["name"], m["value"]))
print()
print("    --- labelValueCountByLabelName (Top 10) ---")
for m in (d.get("labelValueCountByLabelName") or [])[:10]:
    print("      {:45s} {}".format(m["name"], m["value"]))
'

echo
echo "########## 3. 指定 focusLabel 深入分析 user_id ##########"
curl -s -m 30 -G "$VM/api/v1/status/tsdb" \
  --data-urlencode 'topN=5' \
  --data-urlencode 'focusLabel=user_id' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print("    --- 聚焦 user_id ---")
print("    seriesCountByFocusLabelValue (该 label 下各值的序列数):")
for m in (d.get("seriesCountByFocusLabelValue") or [])[:5]:
    print("      {:45s} {}".format(m["name"], m["value"]))
lv=d.get("labelValueCountByLabelName") or []
for m in lv[:5]:
    print("    labelValueCount: {:40s} {}".format(m["name"], m["value"]))
'

echo
echo "########## 4. 实测 relabel 丢弃（写入前治理）##########"
echo "  用 -relabelConfig 全局丢弃 user_id 标签需要在启动时配置，"
echo "  这里先用 MetricsQL 演示「查询时」的降基数效果："
q() {
  echo "--- $1 ---"
  curl -s -m 20 -G "$VM/api/v1/query" \
    --data-urlencode "query=$2" --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,4p'
}
q "4a 原始（按 user_id，5000 条）" 'count(l04_highcard) by (endpoint)'
q "4b 聚合掉 user_id（降为 1 条）" 'sum(l04_highcard) by (endpoint)'

echo
echo "  --- 4c. 用 delete_series 清理高基数数据（运维止血手段）---"
echo "  （实际生产用 /api/v1/admin/tsdb/delete_series，此处先记录命令不执行，"
echo "    因为会真删数据，影响后续实验）"
echo "    curl -X POST 'http://localhost:8428/api/v1/admin/tsdb/delete_series'"
echo "      -d 'match[]=l04_highcard'"

echo
echo "########## 5. 基数限流参数检查 ##########"
echo "  --- 当前的 maxUniqueTimeseries / maxSeries 限制 ---"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_search_max_unique_timeseries|vm_search_max_series"}' \
  --data-urlencode "nocache=1" | python3 "$FMT" | sed -n '2,6p'
echo
echo "  --- 启动日志里的限制值（重启时的输出）---"
docker logs vm-learn 2>&1 | grep -iE 'maxUniqueTimeseries|maxSeries|maxLabelsPerTimeseries' | head -5

echo
echo "########## 6. 总序列数变化 ##########"
echo "  当前 series/count: $(curl -s -m 10 "$VM/api/v1/series/count")"
