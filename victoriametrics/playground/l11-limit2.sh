#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. seriesLimitPerTarget 深挖：目标实际有多少条序列 ==="
echo "  统计 vmagent 自身 /metrics 的序列条数："
cnt=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep -vE "^#" | grep -vE "^\s*$" | wc -l)
echo "     vmagent-self 指标行数 ≈ $cnt  (上限设的是 50，未触发说明按 metric family/序列名计)"
echo "  唯一 __name__ 数量："
uniq=$(curl -s http://localhost:8429/metrics 2>/dev/null | grep -vE "^#" | grep -oE "^[a-zA-Z_:][a-zA-Z0-9_:]*" | sort -u | wc -l)
echo "     唯一指标名 = $uniq"

echo
echo "=== 2. 用更小的上限（5）验证拦截 ==="
docker rm -f vmagent-l5 >/dev/null 2>&1
docker run -d --name vmagent-l5 --network $NET \
  -p 8434:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-l5-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -promscrape.seriesLimitPerTarget=5 \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/0/prometheus \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 22
curl -s http://localhost:8434/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('     %-14s samples=%-6s err=%s' % (
        t['labels'].get('job'), t.get('lastSamplesScraped'), t.get('lastError','')[:60]))
" 2>/dev/null

echo
echo "=== 3. 队列上限：极小队列(50KB) + 不可达后端，观察丢弃 ==="
docker rm -f vmagent-q50 >/dev/null 2>&1
docker run -d --name vmagent-q50 --network $NET \
  -p 8435:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-q50-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://10.255.255.1:8480/insert/0/prometheus \
  -remoteWrite.maxDiskUsagePerURL=50000 \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 25
echo "  --- 观察队列增长与丢弃（上限 50KB）---"
for i in 1 2 3 4 5; do
  sleep 18
  pend=$(curl -s http://localhost:8435/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')
  drop=$(curl -s http://localhost:8435/metrics 2>/dev/null | grep '^vmagent_remotewrite_samples_dropped_total' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')
  dsz=$(docker exec vmagent-q50 sh -c "du -sb /vmagentdata/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
  echo "     T+${i}x18s: pending=${pend}B  dropped=${drop}  队列目录=${dsz}B"
done

echo
echo "=== 4. 日志中的丢弃原因 ==="
docker logs vmagent-q50 2>&1 | grep -iE "dropp|queue|disk" | tail -6 | sed 's/^/  /'

echo
echo "=== 5. 清理 ==="
docker rm -f vmagent-l5 vmagent-q50 >/dev/null 2>&1
echo "  已清理"
