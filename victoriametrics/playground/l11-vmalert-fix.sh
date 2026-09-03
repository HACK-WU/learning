#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 0. 重建 vmalert：数据源改用 vmsel-dedup（8487），不再依赖 vmselect-learn ==="
docker rm -f vmalert-learn >/dev/null 2>&1
docker run -d --name vmalert-learn --network $NET \
  -p 8880:8880 \
  -v $P/rules:/etc/vmalert:ro \
  victoriametrics/vmalert:v1.151.0 \
  -rule=/etc/vmalert/*.yml \
  -datasource.url=http://vmsel-dedup:8481/select/0/prometheus \
  -notifier.url=http://alertmanager-learn:9093 \
  -remoteWrite.url=http://vminsert-learn:8480/insert/0/prometheus/api/v1/write \
  -remoteRead.url=http://vmsel-dedup:8481/select/0/prometheus \
  -httpListenAddr=:8880 \
  -evaluationInterval=5s >/dev/null
sleep 18
echo "  healthz=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8880/healthz)"

echo
echo "=== 1. 记录规则产物是否写入（等 30 秒让规则跑几轮）==="
sleep 30
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=job:up:sum" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     job:up:sum (尚无数据)')
for r in rs: print('     job:up:sum  job=%-14s = %s' % (r['metric'].get('job'), r['value'][1]))
" 2>/dev/null

curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=job:scrape_samples:avg" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     job:scrape_samples:avg (尚无数据)')
for r in rs: print('     job:scrape_samples:avg job=%-14s = %s' % (r['metric'].get('job'), r['value'][1]))
" 2>/dev/null

echo
echo "=== 2. vmalert 规则执行指标 ==="
curl -s http://localhost:8880/metrics 2>/dev/null | grep -E "^vmalert_(rules|iteration|execution|alerts_sent|alert)" | grep -v "^#" | head -25

echo
echo "=== 3. 触发告警：停掉一个纯抓取目标（不影响 vmalert 数据源）==="
echo "  停止 vm-learn（vmsingle job 的目标）..."
docker stop vm-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) STOPPED"
sleep 35

echo "  vmalert 告警状态："
curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
alerts=d['data']['alerts']
print('     活跃告警数:', len(alerts))
for a in alerts:
    print('        %-22s state=%-9s value=%s' % (a.get('name'), a.get('state'), a.get('value','')[:12]))
    print('        summary=%s' % a.get('annotations',{}).get('summary'))
" 2>/dev/null

echo
echo "  Alertmanager 收到："
curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('     告警数:', len(d))
for a in d[:5]:
    lbl=a.get('labels',{})
    print('        %-22s severity=%-9s job=%-12s instance=%s' % (
        lbl.get('alertname'), lbl.get('severity'), lbl.get('job'), lbl.get('instance')))
" 2>/dev/null

echo
echo "=== 4. 恢复并观察 RESOLVED ==="
docker start vm-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) STARTED"
sleep 40
echo "  恢复后 vmalert 告警数: $(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["alerts"]))')"
echo "  恢复后 Alertmanager: $(curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')"
