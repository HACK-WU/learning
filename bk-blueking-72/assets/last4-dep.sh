#!/usr/bin/env bash
NS=blueking
echo "=== 1. 名字里含 apigateway 的 deploy/sts ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | grep -i apigateway | awk '{print "    deploy "$1" "$2}'
kubectl get sts -n $NS --no-headers 2>/dev/null | grep -i apigateway | awk '{print "    sts   "$1" "$2}'

echo ""
echo "=== 2. 名字里含 mysql/mariadb 的 ==="
kubectl get deploy,sts -n $NS --no-headers 2>/dev/null | grep -iE 'mysql|mariadb' | awk '{print "    "$1" "$2}'

echo ""
echo "=== 3. 名字里含 etcd 的 ==="
kubectl get deploy,sts -n $NS --no-headers 2>/dev/null | grep -i etcd | awk '{print "    "$1" "$2}'

echo ""
echo "=== 4. apigateway-dashboard-celery 的环境变量里的依赖地址 ==="
kubectl get deploy -n $NS bk-apigateway-dashboard-celery -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
for e in (c.get('env') or []):
    v=e.get('value') or (e.get('valueFrom') or {}).get('secretKeyRef',{}).get('key','<secret>')
    n=e.get('name','')
    if any(k in n.upper() for k in ['MYSQL','DB_','REDIS','RABBIT','ETCD','BROKER','CELERY']):
        print('    %-28s = %s'%(n,str(v)[:70]))
"

echo ""
echo "=== 5. bkiam-saas-worker 的环境变量里的依赖地址 ==="
kubectl get deploy -n $NS bkiam-saas-worker -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
for e in (c.get('env') or []):
    v=e.get('value') or (e.get('valueFrom') or {}).get('secretKeyRef',{}).get('key','<secret>')
    n=e.get('name','')
    if any(k in n.upper() for k in ['MYSQL','DB_','REDIS','RABBIT','BROKER','CELERY','BK_']):
        print('    %-28s = %s'%(n,str(v)[:70]))
"
