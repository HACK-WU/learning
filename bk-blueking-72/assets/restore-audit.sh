#!/usr/bin/env bash
NS=blueking

echo "=== 1. 内存与集群基线 ==="
free -g | sed -n '2p' | awk '{printf "    used=%sG avail=%sG\n",$3,$7}'
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | head -4

echo ""
echo "=== 2. kafka 当前探针（第3批改的） ==="
kubectl get sts -n $NS bk-kafka -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
for p in ['livenessProbe','readinessProbe','startupProbe']:
    v=c.get(p)
    if v: print('  %-16s %s' % (p+':', json.dumps(v,ensure_ascii=False)))
print('  replicas:', d['spec'].get('replicas'))
" 2>&1

echo ""
echo "=== 3. bkrepo 12 个当前探针（第4批改的） ==="
for d in bk-repo-bkrepo-auth bk-repo-bkrepo-docker bk-repo-bkrepo-gateway \
         bk-repo-bkrepo-generic bk-repo-bkrepo-helm bk-repo-bkrepo-job \
         bk-repo-bkrepo-maven bk-repo-bkrepo-npm bk-repo-bkrepo-opdata \
         bk-repo-bkrepo-pypi bk-repo-bkrepo-replication bk-repo-bkrepo-repository; do
  kubectl get deploy -n $NS $d -o json 2>/dev/null | python3 -c "
import json,sys
try: d=json.load(sys.stdin)
except: sys.exit()
c=d['spec']['template']['spec']['containers'][0]
lp=c.get('livenessProbe') or {}
rp=c.get('readinessProbe') or {}
print('  %-32s live_init=%-5s ready_init=%-5s replicas=%s' % (
  d['metadata']['name'].replace('bk-repo-bkrepo-',''),
  lp.get('initialDelaySeconds','无'), rp.get('initialDelaySeconds','无'),
  d['spec'].get('replicas')))
" 2>&1
done

echo ""
echo "=== 4. 这些组件当前副本（决定还原后会不会立即重启） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | grep -E '^bk-kafka-0|bkrepo' | awk '{printf "    %-46s %s\n",$1,$3}'
echo "  (空=已裁掉，还原探针不会触发重启)"

echo ""
echo "=== 5. helm values 里 kafka 探针原值 ==="
helm get values bk-kafka -n $NS 2>/dev/null | grep -iA3 -E 'probe|liveness|readiness' | head -20
echo "  ---"
helm get values bk-repo -n $NS 2>/dev/null | grep -iA3 -E 'probe|liveness' | head -20
