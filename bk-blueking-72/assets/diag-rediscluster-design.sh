#!/usr/bin/env bash
# 用途：搞清 redis-cluster chart 如何组建集群 + 蓝鲸是否真的依赖它
set -uo pipefail
NS=blueking
B=/root/bk72/install/blueking

echo "===== 1. StatefulSet 的 initContainers / 容器结构 ====="
kubectl get statefulset bk-redis-cluster -n "$NS" -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
spec=d['spec']['template']['spec']
print('  initContainers:', [c['name'] for c in spec.get('initContainers',[])])
print('  containers    :', [c['name'] for c in spec.get('containers',[])])
print('  podManagementPolicy:', spec.get('podManagementPolicy'))
for c in spec.get('containers',[]):
    print('  ---',c['name'],'command/args:')
    print('     cmd:', c.get('command'))
    print('     args:', c.get('args'))
"

echo ""
echo "===== 2. 蓝鲸哪些组件引用 redis-cluster（判断依赖强度）====="
grep -rn "redis-cluster\|redisCluster" "$B/environments/default/"*.yaml* 2>/dev/null | grep -v '^#' | head -20

echo ""
echo "===== 3. values 里 redis-cluster 的开关与配置 ====="
grep -nB2 -A12 'redisCluster\|redis-cluster' "$B/environments/default/values.yaml" 2>/dev/null | head -30

echo ""
echo "===== 4. 集群组建脚本是否存在于镜像内 ====="
kubectl exec bk-redis-cluster-0 -n "$NS" -- sh -c 'ls /opt/bitnami/scripts/ 2>/dev/null; ls /scripts 2>/dev/null' 2>&1 | head -15

echo ""
echo "===== 5. 手动检查各节点能否互通（集群组建前提）====="
kubectl exec bk-redis-cluster-0 -n "$NS" -- sh -c 'getent hosts bk-redis-cluster-headless 2>&1' 2>&1 | head -5
