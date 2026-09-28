#!/usr/bin/env bash
NS=blueking

echo "=== 1. 这 4 个组件的探针 / 资源 / 命令 ==="
for d in bkiam-saas-beat bkiam-saas-worker bk-apigateway-dashboard-beat bk-apigateway-dashboard-celery; do
  echo "--- $d ---"
  kubectl get deploy -n $NS $d -o json 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except: print('     取不到'); raise SystemExit
c=d['spec']['template']['spec']['containers'][0]
print('     镜像:', c.get('image','')[:60])
lp=c.get('livenessProbe'); rp=c.get('readinessProbe')
print('     liveness :', json.dumps(lp,ensure_ascii=False) if lp else '无')
print('     readiness:', json.dumps(rp,ensure_ascii=False) if rp else '无')
r=c.get('resources') or {}
print('     requests :', r.get('requests'))
print('     limits   :', r.get('limits'))
print('     command  :', (c.get('command') or [])[:4])
print('     args     :', (c.get('args') or [])[:4])
"
done

echo ""
echo "=== 2. 依赖组件是否在跑 ==="
for k in bkiam-saas-api bkiam-saas-web bk-apigateway-dashboard-api bk-apigateway-dashboard-web \
         bk-redis bk-rabbitmq bk-mysql bk-apigateway-etcd; do
  s=$(kubectl get deploy,sts -n $NS --no-headers 2>/dev/null | grep -w "$k" | head -1 | awk '{print $2}')
  [ -z "$s" ] && s="不存在"
  printf "    %-32s %s\n" "$k" "$s"
done

echo ""
echo "=== 3. 内存余量 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
