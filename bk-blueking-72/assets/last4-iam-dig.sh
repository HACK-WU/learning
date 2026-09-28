#!/usr/bin/env bash
NS=blueking
B_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-beat' | awk '{print $1}' | head -1)
W_IAM=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep '^bkiam-saas-worker' | awk '{print $1}' | head -1)

echo "=== 1. bkiam beat 全量日志（不 tail） ==="
kubectl logs -n $NS $B_IAM 2>&1 | head -40 | sed 's/^/    /'
echo "    [总行数: $(kubectl logs -n $NS $B_IAM 2>/dev/null | wc -l)]"

echo ""
echo "=== 2. bkiam worker 全量日志 ==="
kubectl logs -n $NS $W_IAM 2>&1 | head -60 | sed 's/^/    /'
echo "    [总行数: $(kubectl logs -n $NS $W_IAM 2>/dev/null | wc -l)]"

echo ""
echo "=== 3. 容器内进程（beat 到底在不在跑） ==="
kubectl exec -n $NS $B_IAM -c bkiam-saas -- ps aux 2>&1 | head -12 | sed 's/^/    /'

echo ""
echo "=== 4. worker 容器内进程 ==="
kubectl exec -n $NS $W_IAM -c bkiam-saas -- ps aux 2>&1 | head -12 | sed 's/^/    /'

echo ""
echo "=== 5. 是否有日志文件（输出可能重定向到文件） ==="
kubectl exec -n $NS $W_IAM -c bkiam-saas -- bash -c 'ls -la /app/logs/ 2>/dev/null | head -20' 2>&1 | sed 's/^/    /'
