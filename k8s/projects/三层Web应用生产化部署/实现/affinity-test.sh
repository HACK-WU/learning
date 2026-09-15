#!/usr/bin/env bash
# ============================================================
# 跨节点反亲和验证 —— 证明单节点下硬反亲和会导致副本 Pending
#
# 结论：本项目刻意不启用 requiredDuringScheduling 反亲和（设计决策 10）。
#       生产多节点环境应该启用，否则副本可能全挤在一个节点。
#
# ⚠️ 复现坑：资源请求必须 >= LimitRange 下限（cpu 50m / mem 64Mi），
#            否则 Pod 根本建不出来，报 FailedCreate 而非 FailedScheduling，
#            你会误以为是反亲和的问题。
#
# 用法： bash affinity-test.sh
# 清理：脚本结束自动删除测试 Deployment
# ============================================================
set -u
NS=shop3t

echo "=== 节点数 ==="
kubectl get nodes --no-headers 2>&1

echo ""
echo "=== 创建强制反亲和的 2 副本 Deployment ==="
cat <<'EOF' | kubectl apply -f - 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: anti-affinity-test
  namespace: shop3t
spec:
  replicas: 2
  selector:
    matchLabels:
      app: anti-test
  template:
    metadata:
      labels:
        app: anti-test
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10002
      containers:
      - name: c
        image: python:3.12-slim
        command: ["sleep", "3600"]
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          seccompProfile:
            type: RuntimeDefault
        resources:
          requests:
            cpu: 60m      # 必须 >= LimitRange 的 50m 下限
            memory: 96Mi  # 必须 >= LimitRange 的 64Mi 下限
          limits:
            cpu: 200m
            memory: 256Mi
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values: ["anti-test"]
            topologyKey: kubernetes.io/hostname
EOF

echo ""
echo "=== 等待 30 秒观察调度结果 ==="
sleep 30
kubectl -n "$NS" get pods -l app=anti-test -o wide --no-headers 2>&1

echo ""
echo "=== FailedScheduling 事件 ==="
kubectl -n "$NS" get events --sort-by=.lastTimestamp 2>&1 \
  | grep -i "FailedScheduling" | tail -3

echo ""
PENDING=$(kubectl -n "$NS" get pod -l app=anti-test \
  --field-selector=status.phase=Pending \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PENDING" ]; then
  echo "✅ 通过：存在 Pending Pod ($PENDING)，硬反亲和在单节点下确实无法调度"
else
  echo "⚠️ 无 Pending Pod —— 若节点数 > 1 属正常（多节点可满足反亲和）"
fi

echo ""
echo "=== 清理测试资源 ==="
kubectl -n "$NS" delete deploy anti-affinity-test --wait=false 2>&1
