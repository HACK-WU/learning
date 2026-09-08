#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440

series() { curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['headStats']['numSeries'])"; }
topn() { curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
  | python3 -c "
import sys,json
d=json.load(sys.stdin)['data']['seriesCountByMetricName'][:4]
print('; '.join(f\"{x['name']}={x['value']}\" for x in d))"; }
mem() { docker stats l10-prom --no-stream --format '{{.MemUsage}}' | awk '{print $1}' | sed 's/MiB//'; }

# 每个场景：清空 Prometheus 数据 + 用指定基数起 app
run_scenario() {
  local label=$1 nuser=$2 nurl=$3 nreq=$4
  docker rm -f l10-prom >/dev/null 2>&1
  docker rm -f l10-app >/dev/null 2>&1
  docker run -d --name l10-app --network $NET \
    -e N_USERS=$nuser -e N_URLS=$nurl -e N_REQIDS=$nreq l10-app >/dev/null 2>&1
  sleep 2
  docker run -d -p $PORT:9090 \
    -v $D/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro \
    --name tmp-prom prom/prometheus:v3.14.0 \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus --web.enable-lifecycle --web.enable-admin-api >/dev/null 2>&1
  docker rename tmp-prom l10-prom >/dev/null 2>&1
  docker network connect $NET l10-prom >/dev/null 2>&1
  for i in $(seq 1 30); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
  sleep 20
  echo "$label|$(series)|$(mem)|$(topn)"
}

echo "############ 实验 1（重置版）：标签值失控的放大倍数 ############"
echo ""
printf "%-38s %8s %10s  %s\n" "场景" "序列数" "内存MiB" "Top 指标"
echo "------------------------------------------------------------------------------------"
run_scenario "A 仅基线（低基数）" 0 0 0
run_scenario "B +5000 user_id" 5000 0 0
run_scenario "C +2000 URL 路径" 0 2000 0
run_scenario "D +1000 request_id(36字符)" 0 0 1000
echo ""
echo "注：每个场景都重建 Prometheus（清空 TSDB），确保测的是增量而非累积"
