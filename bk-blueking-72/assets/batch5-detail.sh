#!/usr/bin/env bash
NS=blueking
echo "=== 1. logstash 资源需求（关键，它是内存大户） ==="
kubectl get sts -n $NS bk-applog-bkapp-logstash -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
r=c.get('resources',{})
print('  image    :',c.get('image'))
print('  requests :',r.get('requests'))
print('  limits   :',r.get('limits'))
lp=c.get('livenessProbe')
print('  liveness :',json.dumps(lp,ensure_ascii=False)[:220] if lp else 'None')
rp=c.get('readinessProbe')
print('  readiness:',json.dumps(rp,ensure_ascii=False)[:220] if rp else 'None')
print('  replicas :',d['spec'].get('replicas'))
" 2>&1

echo ""
echo "=== 2. filebeat ds 状态（DESIRED/CURRENT/READY） ==="
kubectl get ds -n $NS --no-headers 2>/dev/null | grep filebeat | awk '{printf "  %-46s desired=%s current=%s ready=%s\n",$1,$2,$3,$4}'

echo ""
echo "=== 3. logstash 依赖的 configmap ==="
kubectl get cm -n $NS 2>/dev/null | grep -iE 'logstash|applog' | awk '{print "  "$1}'

echo ""
echo "=== 4. ES 集群健康（分开跑，避免卡住） ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s --max-time 10 'http://127.0.0.1:9200/_cluster/health' 2>&1 | head -c 400
echo ""

echo ""
echo "=== 5. ES 已有索引（看日志链路有没有数据流入） ==="
kubectl exec -n $NS bk-elastic-elasticsearch-coordinating-only-0 -- \
  curl -s --max-time 10 'http://127.0.0.1:9200/_cat/indices?v&s=index' 2>&1 | head -20
