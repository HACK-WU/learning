#!/usr/bin/env bash
NS=blueking
MARK="BATCH7-$(date +%s)"

echo "标记: $MARK"
echo ""
echo "=== 1. transfer 连通性（正确 svc 名） ==="
pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-detect-' | head -1 | awk '{print $1}')
kubectl exec -n $NS $pod -- python -c "
import socket
s=socket.socket(); s.settimeout(5)
try:
    s.connect(('bk-monitor-transfer-http',10202)); print('  bk-monitor-transfer-http:10202  OPEN')
except Exception as e: print('  FAIL',str(e)[:50])
" 2>&1 | grep -E 'OPEN|FAIL'

echo ""
echo "=== 2. 推一条真实指标给 transfer（模拟 agent 上报 CPU 99.5%） ==="
kubectl exec -n $NS $pod -- python -c "
import json,urllib.request,time
ts=int(time.time())*1000
body={
 'data_id':1001,
 'data':[{
   'metrics':{'usage':99.5},
   'target':'127.0.0.1',
   'dimension':{'bk_target_ip':'127.0.0.1','mark':'$MARK'},
   'timestamp':ts
 }]
}
req=urllib.request.Request('http://bk-monitor-transfer-http:10202/v2/push/',
  data=json.dumps(body).encode(), headers={'Content-Type':'application/json'})
try:
    r=urllib.request.urlopen(req,timeout=15)
    print('  push HTTP',r.status,'resp:',r.read()[:120].decode())
except Exception as e:
    print('  push EXC:',str(e)[:120])
" 2>&1 | grep -E 'push'

echo ""
echo "=== 3. transfer 日志有没有接住 ==="
kubectl exec -n $NS $(kubectl get pod -n $NS --no-headers | grep '^bk-monitor-transfer-default-' | head -1 | awk '{print $1}') -- \
  sh -c 'tail -20 /app/logs/transfer.log 2>/dev/null || true' 2>&1 | tail -4 | cut -c1-170

echo ""
echo "=== 4. 等 40s，看 detect / alert 反应 ==="
sleep 40
echo "  --- detect ---"
kubectl logs -n $NS $pod --tail=25 2>&1 | grep -i detect | tail -3 | cut -c1-170
echo "  --- alert ---"
apod=$(kubectl get pod -n $NS --no-headers | grep '^bk-monitor-alarm-alert-' | head -1 | awk '{print $1}')
kubectl logs -n $NS $apod --tail=25 2>&1 | grep -iE 'poller|leader' | tail -3 | cut -c1-170

echo ""
echo "=== 5. 最终：influxdb 里能不能查到这条（数据落地） ==="
kubectl exec -n $NS bk-influxdb-0 -- influx -database bkmonitorv3 -execute "SHOW MEASUREMENTS" 2>/dev/null | head -8 | sed 's/^/    /'
