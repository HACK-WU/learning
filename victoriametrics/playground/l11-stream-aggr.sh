#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. seriesLimitPerTarget=5 长期观察（等待缓冲期）==="
docker rm -f vmagent-l5b >/dev/null 2>&1
docker run -d --name vmagent-l5b --network $NET \
  -p 8436:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-l5b-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -promscrape.seriesLimitPerTarget=5 \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/0/prometheus \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 25
for i in 1 2 3; do
  sleep 15
  echo "  T+${i}x15s:"
  curl -s http://localhost:8436/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if t['labels'].get('job')=='vmagent-self':
        print('     vmagent-self samples=%s err=%s' % (t.get('lastSamplesScraped'), t.get('lastError','(无)')[:60]))
" 2>/dev/null
done
echo "  相关日志:"
docker logs vmagent-l5b 2>&1 | grep -iE "series limit|cardinality" | tail -3 | sed 's/^/    /'

echo
echo "=== 2. 流式聚合：采集端预聚合降基数 ==="
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__="up"}'
  interval: 30s
  outputs: [sum_samples, count_samples]
  keep_metric_names: false
EOF
echo "  聚合配置：把 up 按 30s 窗口聚合成 sum/count"

docker rm -f vmagent-aggr >/dev/null 2>&1
docker run -d --name vmagent-aggr --network $NET \
  -p 8437:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/stream-aggr.yml:/etc/stream-aggr.yml:ro \
  -v $P/vmagent-aggr-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/99/prometheus \
  -remoteWrite.streamAggr.config=/etc/stream-aggr.yml \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 45

echo "  --- 聚合产物（写到 tenant 99）---"
for m in "up:sum_samples" "up:count_samples" "up"; do
  curl -s "http://localhost:8487/select/99/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     %-20s (无数据)' % '$m')
for r in rs: print('     %-20s %s = %s' % ('$m', r['metric'], r['value'][1]))
" 2>/dev/null
done

echo
echo "  --- 流式聚合指标 ---"
curl -s http://localhost:8437/metrics 2>/dev/null | grep -E "^vmagent_streamaggr" | grep -v "^#" | head -8 | sed 's/^/  /'

echo
echo "=== 3. 清理 ==="
docker rm -f vmagent-l5b vmagent-aggr >/dev/null 2>&1
echo "  已清理"
