#!/usr/bin/env bash
# 验证 hostNetwork 的 etcd 能否被 NetworkPolicy 收紧（含自动回滚）
# 安全声明: 2379 显式全通；任何健康异常立即删除策略并退出
set -uo pipefail
hr() { printf '\n========== %s ==========\n' "$*"; }

NETPOL=/mnt/d/projects/learning/k8s/子教程/运维专项/assets/etcd-metrics-netpol.yaml
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | head -1 | sed 's|^node/||')
NODE_IP=$(kubectl get node "$CP_NODE" -o jsonpath='{.status.addresses[0].address}')

rollback() {
  hr '!! 检测到异常，立即回滚'
  kubectl delete -f "$NETPOL" --ignore-not-found 2>&1 | tail -1
  kubectl delete pod netpol-probe -n default --ignore-not-found --wait=false >/dev/null 2>&1
  exit 1
}
health() { kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready '; }

hr '0. 基线健康'
echo "Ready 节点数: $(health)  (期望 3)"
[ "$(health)" -ge 3 ] || { echo '基线不健康，终止'; exit 1; }

hr '1. 应用策略（2379 全通 + 2381 仅 monitoring）'
kubectl apply -f "$NETPOL" 2>&1 | tail -2
sleep 10

hr '2. 应用后健康校验（关键：2379 不能被拦）'
H=$(health); echo "Ready 节点数: $H  (期望 3)"
[ "$H" -ge 3 ] || rollback
kubectl -n kube-system get pod -l component=etcd --no-headers
kubectl get --raw=/readyz >/dev/null 2>&1 && echo 'apiserver readyz: OK' || rollback

hr '3. 探针：从 default 命名空间直连 2381（期望被拦）'
kubectl run netpol-probe --image=curlimages/curl:8.11.1 -n default \
  --restart=Never --command -- sleep 300 >/dev/null 2>&1
kubectl wait --for=condition=Ready pod/netpol-probe -n default --timeout=120s 2>&1 | tail -1
kubectl exec netpol-probe -n default -- \
  wget -qO- --timeout=6 "http://$NODE_IP:2381/metrics" >/dev/null 2>&1
echo "default 命名空间访问 2381 exit=$?  (0=能读到=未收紧, 非0=被拦=生效)"

hr '4. 对照组：Prometheus 是否仍能抓到（期望 up=1）'
PROM_POD=$(kubectl -n monitoring get pod -o name | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
  'wget -qO- "http://localhost:9090/api/v1/query?query=up{job=%22kube-etcd%22}" 2>/dev/null' \
  | grep -o '"value":\[[0-9.]*, *"[01]"\]' | head -2

hr '5. 清理探针'
kubectl delete pod netpol-probe -n default --wait=false >/dev/null 2>&1

hr '6. 判定'
echo '第3步非0 且 第4步 up=1  → 生效，保留策略'
echo '第3步为0                → 对 hostNetwork 无效，需删除'

hr '完成'
