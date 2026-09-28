#!/usr/bin/env bash
NS=blueking
echo "=== 1. 节点状态与 NotReady 原因 ==="
kubectl get nodes --no-headers 2>&1 | sed 's/^/  /'
echo ""
for n in k8s-c1-calico-worker k8s-c1-calico-worker2 k8s-c1-calico-control-plane; do
  st=$(kubectl get node $n -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
  msg=$(kubectl get node $n -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
  echo "  $n : $st"
  [ "$st" != "True" ] && echo "       msg: $msg"
done

echo ""
echo "=== 2. Terminating Pod 分布在哪个节点 ==="
kubectl get pods -n $NS --no-headers -o wide 2>/dev/null | awk '$3=="Terminating"{print $7}' | sort | uniq -c | sed 's/^/  /'
echo "  Terminating 总数: $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Terminating"' | wc -l)"

echo ""
echo "=== 3. Terminating 卡了多久 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Terminating"{print $5}' | sort | uniq -c | sort -rn | head -5 | sed 's/^/  /'

echo ""
echo "=== 4. 是否有 deletionTimestamp + finalizer 卡住 ==="
kubectl get pods -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
n=0
for it in d['items']:
    if it['metadata'].get('deletionTimestamp'):
        n+=1
        if n<=3:
            print('   ', it['metadata']['name'], 'finalizers=', it['metadata'].get('finalizers'))
print('   deletionTimestamp 数量:', n)
"

echo ""
echo "=== 5. WSL 内存与 PSI ==="
free -g | sed -n '1,2p' | sed 's/^/  /'
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== 6. CrashLoopBackOff 清单 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="CrashLoopBackOff"{print "  "$1}'
