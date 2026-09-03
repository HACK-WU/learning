#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 0. 先拿到 vm-learn 在 docker 网络里的 IP ==="
VMIP=$(docker inspect vm-learn --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null | head -1)
echo "  vm-learn IP = $VMIP"

echo
echo "=== 1. 用 IP 重写抓取配置 ==="
cat > $P/prometheus-vmagent.yml <<EOF
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: 'vmagent-self'
    static_configs:
      - targets: ['localhost:8429']
  - job_name: 'vmsingle'
    static_configs:
      - targets: ['${VMIP}:8428']
  - job_name: 'vmselect'
    static_configs:
      - targets: ['vmselect-learn:8481']
EOF
cat $P/prometheus-vmagent.yml | grep targets

echo
echo "=== 2. 重启 vmagent 加载新配置 ==="
docker rm -f vmagent-learn >/dev/null 2>&1
docker run -d --name vmagent-learn --network $NET \
  -p 8429:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/vmagent-data:/vmagent-remotewrite-data \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://vminsert-learn:8480/insert/0/prometheus/api/v1/write \
  -remoteWrite.maxDiskUsagePerURL=209715200 \
  -remoteWrite.tmpDataPath=/vmagent-remotewrite-data \
  -httpListenAddr=:8429 \
  -loggerLevel=INFO >/dev/null
sleep 15

echo
echo "=== 3. 检查三个 target 的健康状态 ==="
curl -s http://localhost:8429/api/v1/targets 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    print('  %-14s %-24s health=%-4s samples=%-6s err=%s' % (
        t['labels'].get('job'), t['labels'].get('instance'),
        t['health'], t.get('lastSamplesScraped'), t.get('lastError','')[:40]))
" 2>/dev/null
