#!/usr/bin/env bash
NS=blueking

echo "=== 1. 节点 ==="
kubectl get nodes --no-headers 2>/dev/null | awk '{printf "    %-28s %s\n",$1,$2}'

echo ""
echo "=== 2. Pod 状态 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | awk '{print "    "$2" "$1}'

echo ""
echo "=== 3. 内存 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'

echo ""
echo "=== 4. 页面 ==="
for d in paas.example.com bkpaas.paas.example.com bkiam.paas.example.com bkmonitor.paas.example.com; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$d/" 2>/dev/null)
  printf "    %-30s %s\n" "$d" "$c"
done

echo ""
echo "=== 5. 存储数据真实性 ==="
kubectl exec -n $NS bk-influxdb-0 -- influx -database bkmonitorv3 -execute "SHOW MEASUREMENTS" 2>/dev/null | grep -v '^name' | grep -v '^---' | grep . | head -4 | sed 's/^/    influx: /'
kubectl exec -n $NS bk-kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null | grep . | head -4 | sed 's/^/    kafka topic: /'

echo ""
echo "=== 6. 已起组件数 ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l | xargs echo "    deploy 在跑:"
kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l | xargs echo "    sts 在跑:"

echo ""
echo "=== 7. 探针残留终检（全命名空间 deploy） ==="
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); bad=0
for it in d['items']:
    for c in it['spec']['template']['spec']['containers']:
        lp=c.get('livenessProbe') or {}
        if lp.get('initialDelaySeconds')==180 or lp.get('failureThreshold')==12: bad+=1
print('    放宽值残留: %d'%bad)
"
