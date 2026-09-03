#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. 重建 vmalert，remoteWrite.url 去掉 /api/v1/write 后缀 ==="
docker rm -f vmalert-learn >/dev/null 2>&1
docker run -d --name vmalert-learn --network $NET \
  -p 8880:8880 \
  -v $P/rules:/etc/vmalert:ro \
  victoriametrics/vmalert:v1.151.0 \
  -rule=/etc/vmalert/*.yml \
  -datasource.url=http://vmsel-dedup:8481/select/0/prometheus \
  -notifier.url=http://alertmanager-learn:9093 \
  -remoteWrite.url=http://vminsert-learn:8480/insert/0/prometheus \
  -remoteRead.url=http://vmsel-dedup:8481/select/0/prometheus \
  -httpListenAddr=:8880 \
  -evaluationInterval=5s >/dev/null
sleep 20

echo "  日志错误数: $(docker logs vmalert-learn 2>&1 | grep -c 'unsupported path')"
echo "  (0 = 路径已正确)"

echo
echo "=== 2. 记录规则产物（等 40 秒）==="
sleep 40
for m in "job:up:sum" "job:scrape_samples:avg"; do
curl -s "http://localhost:8481/select/0/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
rs=d['data']['result']
if not rs: print('     $m : (无数据)')
for r in rs: print('     $m : job=%-14s = %s' % (r['metric'].get('job'), r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 3. 记录规则写入是否带 vmalert 标记 ==="
curl -s "http://localhost:8481/select/0/prometheus/api/v1/series?match[]=job:up:sum" 2>/dev/null | head -c 400
echo

echo
echo "=== 4. 触发告警：停掉 vm-learn ==="
docker stop vm-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) vm-learn STOPPED"
sleep 35

curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
alerts=d['data']['alerts']
print('  vmalert 活跃告警数:', len(alerts))
for a in alerts:
    print('     %-22s state=%-9s severity=%s' % (a.get('name'), a.get('state'), a['labels'].get('severity')))
    print('        summary=%s' % a.get('annotations',{}).get('summary'))
    print('        activeAt=%s value=%s' % (str(a.get('activeAt',''))[:19], a.get('value','')[:8]))
" 2>/dev/null

echo
echo "=== 5. Alertmanager 收到 ==="
curl -s http://localhost:9093/api/v2/alerts 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  Alertmanager 告警数:', len(d))
for a in d[:5]:
    lbl=a.get('labels',{})
    print('     %-22s severity=%-9s job=%-12s status=%s' % (
        lbl.get('alertname'), lbl.get('severity'), lbl.get('job'),
        a.get('status',{}).get('state')))
" 2>/dev/null

echo
echo "=== 6. 恢复并观察 resolved ==="
docker start vm-learn >/dev/null 2>&1
echo "     $(date +%H:%M:%S) vm-learn STARTED"
sleep 45
echo "  恢复后 vmalert 告警数: $(curl -s http://localhost:8880/api/v1/alerts 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)["data"]["alerts"]))' 2>/dev/null)"
echo "  fired_total: $(curl -s http://localhost:8880/metrics 2>/dev/null | grep '^vmalert_alerts_fired_total' | awk '{print $2}')"
echo "  sent_total : $(curl -s http://localhost:8880/metrics 2>/dev/null | grep '^vmalert_alerts_sent_total' | grep -v '^#' | awk '{print $2}')"
