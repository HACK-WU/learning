#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 0. 确认后端已恢复、数据无丢失 ==="
echo "  dropped = $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_samples_dropped_total' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')"
echo "  pending = $(curl -s http://localhost:8429/metrics 2>/dev/null | grep '^vmagent_remotewrite_pending_data_bytes' | grep -v '^#' | awk '{s+=$NF} END {print s+0}')"

echo
echo "=== 1. 准备告警规则文件 ==="
mkdir -p $P/rules
cat > $P/rules/alerts.yml <<'EOF'
groups:
  - name: l11-basic
    rules:
      - alert: TargetDown
        expr: up == 0
        for: 10s
        labels:
          severity: critical
        annotations:
          summary: "抓取目标 {{ $labels.instance }} 已下线"
          description: "job={{ $labels.job }} 已经连续 10 秒 up==0"

      - alert: VmagentQueueBackedUp
        expr: vmagent_remotewrite_pending_data_bytes > 100
        for: 5s
        labels:
          severity: warning
        annotations:
          summary: "vmagent 持久化队列积压 {{ $value }} 字节"
EOF

cat > $P/rules/recording.yml <<'EOF'
groups:
  - name: l11-recording
    interval: 10s
    rules:
      - record: job:up:sum
        expr: sum by (job) (up)
      - record: job:scrape_samples:avg
        expr: avg by (job) (scrape_samples_scraped)
EOF
echo "  告警规则 alerts.yml 与记录规则 recording.yml 已写入"

echo
echo "=== 2. 启动 Alertmanager ==="
cat > $P/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m
route:
  receiver: 'devnull'
  group_wait: 5s
  group_interval: 10s
  repeat_interval: 30s
receivers:
  - name: 'devnull'
EOF
docker rm -f alertmanager-learn >/dev/null 2>&1
docker run -d --name alertmanager-learn --network $NET \
  -p 9093:9093 \
  -v $P/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro \
  prom/alertmanager:v0.27.0 \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager >/dev/null
sleep 10
echo "  Alertmanager: $(docker ps --filter name=alertmanager-learn --format '{{.Status}}')"
echo "  /-/ready: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:9093/-/ready)"

echo
echo "=== 3. 启动 vmalert ==="
docker rm -f vmalert-learn >/dev/null 2>&1
docker run -d --name vmalert-learn --network $NET \
  -p 8880:8880 \
  -v $P/rules:/etc/vmalert:ro \
  victoriametrics/vmalert:v1.151.0 \
  -rule=/etc/vmalert/*.yml \
  -datasource.url=http://vmselect-learn:8481/select/0/prometheus \
  -notifier.url=http://alertmanager-learn:9093 \
  -remoteWrite.url=http://vminsert-learn:8480/insert/0/prometheus/api/v1/write \
  -remoteRead.url=http://vmselect-learn:8481/select/0/prometheus \
  -httpListenAddr=:8880 \
  -evaluationInterval=5s >/dev/null
sleep 15
echo "  vmalert: $(docker ps --filter name=vmalert-learn --format '{{.Status}}')"
echo "  /healthz: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/healthz)"

echo
echo "=== 4. vmalert 加载了哪些规则 ==="
curl -s http://localhost:8880/api/v1/rules 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
groups=d['data']['groups']
print('  规则组数:', len(groups))
for g in groups:
    print('   [%s] 文件=%s interval=%ss 规则数=%d' % (g['name'], g.get('file','').split('/')[-1], g.get('interval'), len(g['rules'])))
    for r in g['rules']:
        kind='alert' if 'alert' in r else 'record'
        name=r.get('alert') or r.get('record')
        print('       %-6s %-32s state=%s' % (kind, name, r.get('state','-')))
" 2>/dev/null
