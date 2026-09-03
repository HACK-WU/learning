#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net
SEL=http://localhost:8481/select/0/prometheus

echo "=== 1. Prometheus 的 remote_write 队列配置（内存 / 按样本数）==="
docker exec prom-learn sh -c "grep -A8 'queue_config' /etc/prometheus/prometheus.yml 2>/dev/null" 2>/dev/null | sed 's/^/  /'
echo "  --- prom-learn 是否配了 remote_write ---"
docker exec prom-learn sh -c "grep -c 'remote_write' /etc/prometheus/prometheus.yml 2>/dev/null" | sed 's/^/  count=/'

echo
echo "=== 2. 兼容性端点对照表 ==="
printf "  %-30s %-12s %-12s %-12s\n" "端点" "vmagent:8429" "vmalert:8880" "prom:9090"
printf "  %-30s %-12s %-12s %-12s\n" "--------------------------------------------" "------------" "------------" "------------"
for ep in "/api/v1/targets" "/api/v1/status/config" "/api/v1/status/flags" "/-/reload" "/config" "/service-discovery" "/api/v1/query"; do
  a=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8429$ep" 2>/dev/null)
  b=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:8880$ep" 2>/dev/null)
  c=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:9090$ep" 2>/dev/null)
  printf "  %-30s %-12s %-12s %-12s\n" "$ep" "$a" "$b" "$c"
done
echo "  (POST /-/reload 为写操作，上表 GET 探测仅看路由是否存在)"

echo
echo "=== 3. vmalert 是否有 /healthz ==="
echo "  vmalert /healthz: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/healthz)  body=$(curl -s http://localhost:8880/healthz 2>/dev/null | head -c 60)"
echo "  vmalert /health : $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/health)"
echo "  prometheus /healthz: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:9090/-/healthy)"

echo
echo "=== 4. 流式聚合（stream aggregation）==="
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__="up"}'
  interval: 30s
  outputs: [sum_samples, count_samples]
  keep_metric_names: false
EOF
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
sleep 50
echo "  --- tenant 99 中的聚合产物（8487 = dedup 节点）---"
for m in "up:sum_samples" "up:count_samples" "up"; do
curl -s "http://localhost:8487/select/99/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     %-20s (无数据)' % '$m')
for r in rs: print('     %-20s %-42s = %s' % ('$m', str(r['metric'])[:40], r['value'][1]))
" 2>/dev/null
done
echo "  --- 流式聚合自身指标 ---"
curl -s http://localhost:8437/metrics 2>/dev/null | grep -E "^vmagent_streamaggr" | grep -v "^#" | head -6 | sed 's/^/    /'
echo "  --- 对照：tenant 0 中同名 up 的原始点数 ---"
curl -s "http://localhost:8487/select/0/prometheus/api/v1/query?query=count(up)" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
print('     tenant 0 中 up 序列数 =', rs[0]['value'][1] if rs else 'N/A')
" 2>/dev/null

echo
echo "=== 5. 队列故障演练（核心数据复核）==="
echo "  故障前基线："
echo "    blocks_sent = $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_blocks_sent_total' | grep -v '^#' | awk '{print $NF}')"
echo "    pending     = $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{print $NF}')"
echo "    retries     = $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_retries_count_total' | grep -v '^#' | awk '{print $NF}')"

echo "  $(date +%H:%M:%S) 停止全部 vminsert（真正断开后端）"
docker stop vminsert-learn vminsert-learn2 >/dev/null 2>&1
for i in 1 2 3 4 5; do
  sleep 30
  pend=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{print $NF}')
  ret=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_retries_count_total' | grep -v '^#' | awk '{print $NF}')
  drop=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_samples_dropped_total' | grep -v '^#' | awk '{print $NF}')
  dsz=$(docker exec vmagent-learn sh -c "du -sb /vmagent-remotewrite-data/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
  echo "    故障 ${i}x30s($((i*30))s): pending=${pend}B retries=${ret} dropped=${drop} 队列目录=${dsz}B"
done

echo "  $(date +%H:%M:%S) 恢复后端"
docker start vminsert-learn vminsert-learn2 >/dev/null 2>&1
for i in 1 2 3 4; do
  sleep 10
  pend=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{print $NF}')
  blk=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_blocks_sent_total' | grep -v '^#' | awk '{print $NF}')
  drop=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_samples_dropped_total' | grep -v '^#' | awk '{print $NF}')
  echo "    恢复 +${i}0s: pending=${pend}B blocks_sent=${blk} dropped=${drop}"
done
