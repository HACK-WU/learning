#!/bin/bash
# 排查：Influx 写入 HTTP 204 但 0 行的原因
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
Q() { curl -s --max-time 15 --data-urlencode "query=$1" http://localhost:8428/api/v1/query; }

echo "=============================================="
echo " D1 嫌疑1：relabel.yaml 是不是把数据丢了"
echo "=============================================="
echo "-- relabel.yaml 内容 --"
cat relabel.yaml 2>&1
echo
echo "-- stream-aggr.yaml 内容 --"
cat stream-aggr.yaml 2>&1

echo
echo "=============================================="
echo " D2 嫌疑2：时间戳精度 / 时间范围"
echo "=============================================="
echo "  当前 UTC: $(date -u '+%Y-%m-%d %H:%M:%S')"
echo "  当前 epoch 秒: $(date +%s)"
echo "  写入样本时间戳: 1788336921 (sec)"
echo "  换算: $(date -u -d @1788336921 '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
echo
echo "  写入样本时间戳(纳秒): 1788336921000000000"
NS=1788336921000000000
echo "  纳秒长度: ${#NS} 位 (应为 19 位)"

echo
echo "=============================================="
echo " D3 嫌疑3：-retentionPeriod=1d 之外的数据被拒"
echo "=============================================="
echo "  retentionPeriod=1d，所以只保留最近 24h。"
echo "  1 天前 = $(date -u -d '1 day ago' '+%Y-%m-%d %H:%M:%S') (epoch $(date -d '1 day ago' +%s))"
echo "  我们的时间戳 1788336921 在范围内吗？"
NOW=$(date +%s)
echo "  差值: $((NOW - 1788336921)) 秒（应 < 86400）"

echo
echo "=============================================="
echo " D4 直接用最简写入测试，逐步排查"
echo "=============================================="
NOW=$(date +%s)
echo "-- 测试 A：不带时间戳（用服务器当前时间）--"
printf 'l06_probe_a value=1\n' > /tmp/pa.txt
curl -s -X POST --max-time 20 --data-binary @/tmp/pa.txt 'http://localhost:8428/write' \
  -o /dev/null -w '  HTTP: %{http_code}\n'

echo "-- 测试 B：带秒级时间戳 --"
printf 'l06_probe_b value=1 %s\n' "$NOW" > /tmp/pb.txt
curl -s -X POST --max-time 20 --data-binary @/tmp/pb.txt 'http://localhost:8428/write' \
  -o /dev/null -w '  HTTP: %{http_code}\n'

echo "-- 测试 C：带纳秒时间戳（19位）--"
printf 'l06_probe_c value=1 %s000000000\n' "$NOW" > /tmp/pc.txt
curl -s -X POST --max-time 20 --data-binary @/tmp/pc.txt 'http://localhost:8428/write' \
  -o /dev/null -w '  HTTP: %{http_code}\n'

echo "-- 测试 D：带毫秒时间戳（13位）--"
printf 'l06_probe_d value=1 %s000\n' "$NOW" > /tmp/pd.txt
curl -s -X POST --max-time 20 --data-binary @/tmp/pd.txt 'http://localhost:8428/write' \
  -o /dev/null -w '  HTTP: %{http_code}\n'

sleep 3
echo
echo "-- 四个探针分别查得到吗 --"
for m in l06_probe_a l06_probe_b l06_probe_c l06_probe_d; do
  R=$(Q "count($m)" | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
print(int(float(d[0]["value"][1])) if d else 0)' 2>/dev/null)
  echo "  $m : $R 条序列"
done

echo
echo "-- influx 累计写入行数（看是否涨了）--"
Q 'sum(vm_rows_inserted_total) by (type)' | python3 -c 'import json,sys
d=json.load(sys.stdin)["data"]["result"]
for r in d:
    v=float(r["value"][1])
    if v>0: print("  %-18s %12.0f" % (r["metric"].get("type","-"), v))' 2>/dev/null
