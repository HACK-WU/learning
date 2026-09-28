#!/usr/bin/env bash
NS=blueking

echo "=== 1. 真实 svc 名（含 transfer 的） ==="
kubectl get svc -n $NS --no-headers 2>/dev/null | awk '{print $1}' | grep -iE 'transfer|monitor' | head -10 | sed 's/^/    /'

echo ""
echo "=== 2. transfer svc 完整信息 ==="
kubectl get svc -n $NS 2>/dev/null | grep -i transfer | awk '{print "    "$1" "$2" "$5}'

echo ""
echo "=== 3. 从 detect pod 内部Ping通 transfer（用正确名字） ==="
pod=$(kubectl get pod -n $NS --no-headers 2>/dev/null | grep '^bk-monitor-alarm-detect-' | head -1 | awk '{print $1}')
for h in bk-monitor-transfer-default bk-monitor-transfer bk-transfer; do
  r=$(kubectl exec -n $NS $pod -- python -c "
import socket
s=socket.socket(); s.settimeout(4)
try:
    s.connect(('$h',10202)); print('OPEN')
except Exception as e: print('FAIL '+str(e)[:30])
" 2>/dev/null)
  printf "    %-32s %s\n" "$h" "$r"
done

echo ""
echo "=== 4. detect 实际读的 redis key（告警检测的入口） ==="
kubectl exec -n $NS $pod -- python -c "
import redis
r=redis.Redis(host='bk-redis-master',port=6379,password='blueking',db=0)
ks=r.keys('*')[:15]
print('  db0 前15个key:')
for k in ks: print('    ',k.decode()[:70])
" 2>&1 | grep -vE 'Warning|warn' | head -18
