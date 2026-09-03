#!/usr/bin/env bash
# 课 4 步骤 2：多协议接入实测（InfluxDB line protocol / Graphite / OpenTSDB / CSV import）
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py

q() {
  echo "--- $1 ---"
  echo "    query: $2"
  curl -s -m 15 -G "$VM/api/v1/query" \
    --data-urlencode "query=$2" --data-urlencode "nocache=1" | python3 "$FMT"
}

echo "########## A. InfluxDB line protocol ##########"
echo "  端点：POST /write （VM 内置，无需额外端口）"
NOW=$(date +%s)
PAYLOAD="cpu_load_short,host=server01,region=us-west value=0.64 ${NOW}000000000
cpu_load_short,host=server02,region=us-west value=0.51 ${NOW}000000000
temperature,machine=unit42,type=assembly external=25,internal=37 ${NOW}000000000"
echo "  写入内容:"
echo "$PAYLOAD" | sed 's/^/    /'
echo "  请求:"
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" \
  -X POST "$VM/write" --data-binary "$PAYLOAD"

echo
q "A1 查 cpu_load_short（Influx 格式写入）" 'cpu_load_short'
q "A2 查 temperature（多字段自动展开）"     'temperature'

echo
echo "########## B. Graphite plaintext protocol ##########"
echo "  注意：Graphite 需要独立监听端口（-graphiteListenAddr），默认关闭"
echo "  检查当前 VM 是否开启了 graphite 端口 2003:"
if (echo > /dev/tcp/127.0.0.1/2003) 2>/dev/null; then
  echo "    2003 端口已监听，写入测试中..."
  echo "l04.graphite.test 42 $(date +%s)" | timeout 5 nc -q0 127.0.0.1 2003 2>/dev/null
  sleep 1
  q "B1 查 graphite 指标" '{__name__=~"l04.graphite.*"}'
else
  echo "    2003 未监听 → Graphite 协议默认关闭，需重启容器加 -graphiteListenAddr=:2003"
  echo "    这正是本课要讲的：不同协议的启用方式不同"
fi

echo
echo "########## C. OpenTSDB 协议 ##########"
echo "  同样需要 -opentsdbListenAddr / -opentsdbHTTPListenAddr，默认关闭"
if (echo > /dev/tcp/127.0.0.1/4242) 2>/dev/null; then
  echo "    4242 已监听"
else
  echo "    4242 未监听 → OpenTSDB 默认关闭"
fi
echo "  OpenTSDB HTTP 端点 /api/put 实测:"
echo '{"metric":"l04.opentsdb.test","timestamp":'"$(date +%s)"',"value":18,"tags":{"host":"web01"}}' \
  > /tmp/l04_opentsdb.json
curl -s -m 10 -o /dev/null -w "    /api/put http=%{http_code}\n" \
  -X POST "$VM/api/put" --data-binary @/tmp/l04_opentsdb.json

echo
echo "########## D. CSV import（/api/v1/import/csv）##########"
echo "  格式: METRIC_NAME,tag1,tag2,...,value,timestamp"
CSV="l04_csv_test,host,h1,dc,dc1,3.14,${NOW}
l04_csv_test,host,h2,dc,dc1,2.71,${NOW}"
echo "$CSV" | sed 's/^/    /'
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" \
  -X POST "$VM/api/v1/import/csv" \
  --data-urlencode 'format=1:metric:host,2:metric:dc,3:metric:value:3,4:time:unix_s' \
  --data-binary "$CSV"
sleep 2
q "D1 查 CSV 导入的指标" 'l04_csv_test'

echo
echo "########## E. 原生 Prometheus 文本格式（/api/v1/import/prometheus）##########"
curl -s -m 15 -o /dev/null -w "    http=%{http_code}\n" \
  -X POST "$VM/api/v1/import/prometheus" \
  --data-binary "l04_native_test{job=\"import\"} 99 ${NOW}"
sleep 2
q "E1 查原生导入" 'l04_native_test'

echo
echo "########## F. 汇总：本次写入的 l04_ 前缀指标 ##########"
q "F1 所有 l04 指标" '{__name__=~"l04.*"}'
