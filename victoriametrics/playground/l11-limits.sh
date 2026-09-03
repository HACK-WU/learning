#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. 实测：seriesLimitPerTarget（单目标序列数上限）==="
docker rm -f vmagent-limit >/dev/null 2>&1
docker run -d --name vmagent-limit --network $NET \
  -p 8431:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-limit-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -promscrape.seriesLimitPerTarget=50 \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/0/prometheus \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 20

echo "  --- 抓取是否被限制（目标样本数 vs 上限 50）---"
curl -s http://localhost:8431/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('     %-14s samples=%-6s err=%s' % (
        t['labels'].get('job'), t.get('lastSamplesScraped'), t.get('lastError','')[:55]))
" 2>/dev/null

echo
echo "=== 2. 实测：maxScrapeSize（响应体大小上限）==="
docker rm -f vmagent-sz >/dev/null 2>&1
docker run -d --name vmagent-sz --network $NET \
  -p 8432:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-sz-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -promscrape.maxScrapeSize=1000 \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/0/prometheus \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 20
echo "  --- 上限 1000 字节，实际响应远大于此 ---"
curl -s http://localhost:8432/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('     %-14s samples=%-6s err=%s' % (
        t['labels'].get('job'), t.get('lastSamplesScraped'), t.get('lastError','')[:55]))
" 2>/dev/null

echo
echo "=== 3. 队列超限时的数据丢弃行为 ==="
echo "  启动一个 maxDiskUsagePerURL 极小的 vmagent（1MB）"
docker rm -f vmagent-tinyq >/dev/null 2>&1
docker run -d --name vmagent-tinyq --network $NET \
  -p 8433:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-tinyq-data:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://10.255.255.1:8480/insert/0/prometheus \
  -remoteWrite.maxDiskUsagePerURL=1000000 \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 25
echo "  --- 指向不可达地址，观察队列与丢弃 ---"
for i in 1 2 3; do
  sleep 20
  pend=$(curl -s http://localhost:8433/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')
  drop=$(curl -s http://localhost:8433/metrics 2>/dev/null | grep '^vmagent_remotewrite_samples_dropped_total' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')
  dsz=$(docker exec vmagent-tinyq sh -c "du -sb /vmagentdata/persistent-queue/* 2>/dev/null | awk '{s+=\$1} END {print s+0}'")
  echo "     T+${i}x20s: pending=${pend}B  dropped=${drop}  队列目录=${dsz}B"
done

echo
echo "=== 4. 清理临时容器 ==="
docker rm -f vmagent-limit vmagent-sz vmagent-tinyq >/dev/null 2>&1
echo "  已清理"
