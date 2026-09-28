#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 在 bkrepo-auth 镜像里找 init-mongodb.sh ====="
AP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | grep Running | awk '{print $1}' | head -1)
kubectl exec $AP -n $NS -- bash -c "ls -la /data/workspace/ 2>/dev/null; find / -name 'init-mongodb*' -maxdepth 5 2>/dev/null | head -5" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 在 repository 镜像里找 ====="
RP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-repository' | grep Running | awk '{print $1}' | head -1)
kubectl exec $RP -n $NS -- bash -c "ls -la /data/workspace/ 2>/dev/null; find / -name 'init-mongodb*' -maxdepth 5 2>/dev/null | head -5" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 测试 bkrepo-auth 镜像能否直接跑（用 sh 探测）====="
cat <<'EOF' | kubectl apply -f - 2>&1 | sed 's/^/  /'
apiVersion: v1
kind: Pod
metadata:
  name: init-mongo-probe
  namespace: blueking
spec:
  restartPolicy: Never
  containers:
  - name: probe
    image: hub.bktencent.com/blueking/bkrepo-auth:v3.3.1-beta.1
    command: ['/bin/sh','-c']
    args: ['echo "=== 找脚本 ==="; ls /data/workspace/ 2>&1; find / -name "init-mongodb.sh" 2>/dev/null | head -3; echo "=== 试执行 ==="; /data/workspace/init-mongodb.sh 2>&1 | head -20 || echo "执行失败"; sleep 5']
EOF

echo ""
echo "===== 4. 等它跑完并看输出 ====="
for i in $(seq 1 30); do
  S=$(kubectl get pod init-mongo-probe -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Succeeded" ] || [ "$S" = "Failed" ] && { echo "  终态: $S"; break; }
  sleep 3
done
kubectl logs init-mongo-probe -n $NS 2>&1 | sed 's/^/    /'
