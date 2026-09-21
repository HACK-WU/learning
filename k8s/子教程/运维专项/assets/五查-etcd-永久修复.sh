#!/usr/bin/env bash
# etcd metrics 永久修复 + 加固 + 验证
# 用法: bash 五查-etcd-永久修复.sh [fix|verify-netpol|test]
# 安全声明: fix 会改静态清单使 kubelet 重启 etcd 一次；其余只读
set -uo pipefail
hr() { printf '\n========== %s ==========\n' "$*"; }

CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | head -1 | sed 's|^node/||')
CP_CTR="$CP_NODE"
MANIFEST=/etc/kubernetes/manifests/etcd.yaml
BACKUP=/tmp/etcd.yaml.orig

do_fix() {
  hr "0. 备份（已有则跳过）"
  docker exec "$CP_CTR" test -f "$BACKUP" && echo "备份已存在" || \
    docker exec "$CP_CTR" cp "$MANIFEST" "$BACKUP"

  hr '1. 改监听 127.0.0.1:2381 → 0.0.0.0:2381（永久）'
  docker exec "$CP_CTR" sed -i 's|--listen-metrics-urls=http://127.0.0.1:2381|--listen-metrics-urls=http://0.0.0.0:2381|' "$MANIFEST"
  docker exec "$CP_CTR" grep -n 'listen-metrics-urls' "$MANIFEST"

  hr '2. 等 kubelet 重建 etcd'
  for i in $(seq 1 12); do
    S=$(kubectl -n kube-system get pod -l component=etcd --no-headers 2>/dev/null | awk '{print $3}')
    echo "  [$((i*5))s] $S"
    [ "$S" = "Running" ] && break
    sleep 5
  done

  hr '3. 等 Prometheus 抓取 2 轮（约 65s）'
  sleep 65

  hr '4. 验证采集恢复'
  PROM_POD=$(kubectl -n monitoring get pod -o name | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
  q(){ kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
    "wget -qO- 'http://localhost:9090/api/v1/query?query=$1' 2>/dev/null" | head -c 300; echo; }
  echo '--- up ---';                              q 'up{job="kube-etcd"}'
  echo '--- etcd_server_has_leader ---';          q 'etcd_server_has_leader'
  echo '--- 占用率 ---';                           q '(etcd_mvcc_db_total_size_in_bytes/etcd_server_quota_backend_bytes)*100'
}

do_test() {
  hr 'T. 暴露面实测：从集群内另一个 Pod 直连 2381（无认证能读到什么）'
  kubectl run netpol-probe --image=curlimages/curl:8.11.1 -n default \
    --restart=Never --command -- sleep 600 >/dev/null 2>&1
  kubectl wait --for=condition=Ready pod/netpol-probe -n default --timeout=120s 2>&1 | tail -1
  NODE_IP=$(kubectl get node "$CP_NODE" -o jsonpath='{.status.addresses[0].address}')
  echo "目标: http://$NODE_IP:2381/metrics"
  kubectl exec netpol-probe -n default -- \
    wget -qO- --timeout=8 "http://$NODE_IP:2381/metrics" 2>/dev/null | head -5
  echo "--- exit=$? (0=能读到, 非0=被拦) ---"
  kubectl delete pod netpol-probe -n default --wait=false >/dev/null 2>&1
}

case "${1:-fix}" in
  fix)           do_fix ;;
  test)          do_test ;;
  verify-netpol) do_test ;;
  *)             echo "用法: $0 [fix|test]" ;;
esac
hr '完成'
