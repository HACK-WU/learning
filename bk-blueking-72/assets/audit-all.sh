#!/usr/bin/env bash
NS=blueking
echo "=== 1. Pod 全量状态分桶 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | sed 's/^/  /'

echo ""
echo "=== 2. 未 Ready 的 Pod（含非 0/1、CrashLoop） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$2!=$3 || $3!="Running" && $3!="Completed"' | head -30 | sed 's/^/  /'

echo ""
echo "=== 3. 全部 Deployment 副本数 vs Ready 数（0/0 即被裁的） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '{split($2,a,"/"); if(a[2]==0) print "  [已裁] "$1; else if(a[1]!=a[2]) print "  [异常] "$1" "$2}' | head -50

echo ""
echo "=== 4. 有 Service 的 deploy（前台，影响页面）是否都 Ready ==="
kubectl get deploy -n $NS --no-headers -o custom-columns='NAME:.metadata.name,R:.status.readyReplicas' 2>/dev/null | awk '$2=="0"||$2=="<none>"{print $1}' > /tmp/noready.txt
SVCSEL=$(kubectl get svc -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
s=set()
for it in d['items']:
    sel=it['spec'].get('selector') or {}
    for k,v in sel.items(): s.add('%s=%s'%(k,v))
print(' '.join(sorted(s)))
")
echo "  Service selector 数: $(echo $SVCSEL | wc -w)"
echo ""
echo "  --- 有 Service 但未 Ready 的 deploy ---"
for sel in $SVCSEL; do
  kubectl get deploy -n $NS -l "$sel" --no-headers 2>/dev/null | awk '$2!=$3{print "    "$1" "$2}'
done | sort -u | head -20

echo ""
echo "=== 5. 页面实测 ==="
for d in paas.example.com bkpaas.paas.example.com bkmonitor.paas.example.com bkrepo.paas.example.com bknodeman.paas.example.com bkiam.paas.example.com apigw.paas.example.com bkcmdb.paas.example.com bkuser.paas.example.com bklog.paas.example.com; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://$d/" 2>/dev/null)
  printf "  %-32s %s\n" "$d" "$code"
done
