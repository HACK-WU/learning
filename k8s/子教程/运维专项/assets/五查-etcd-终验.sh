#!/usr/bin/env bash
# 永久修复后终验：采集 + 告警规则 + 交叉核对 + 暴露面如实记录
set -uo pipefail
hr() { printf '\n========== %s ==========\n' "$*"; }

PROM_POD=$(kubectl -n monitoring get pod -o name | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
q(){ kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
  "wget -qO- 'http://localhost:9090/api/v1/query?query=$1' 2>/dev/null" | head -c 300; echo; }

hr '1. 采集恢复（核心指标）'
echo '--- up{job=kube-etcd} ---';                q 'up{job="kube-etcd"}'
echo '--- etcd_server_has_leader ---';           q 'etcd_server_has_leader'
echo '--- db_total_size ---';                    q 'etcd_mvcc_db_total_size_in_bytes'
echo '--- quota_backend_bytes ---';              q 'etcd_server_quota_backend_bytes'
echo '--- 占用率 ---';                            q '(etcd_mvcc_db_total_size_in_bytes/etcd_server_quota_backend_bytes)*100'

hr '2. 告警规则现在能用吗（Prometheus 已加载的 etcd 规则）'
kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
  'wget -qO- "http://localhost:9090/api/v1/rules" 2>/dev/null' \
  | tr ',' '\n' | grep -o '"name":"etcd[A-Za-z]*"' | sort -u | head -20

hr '3. 与 etcdctl 交叉核对（两口径应一致）'
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=json 2>/dev/null | tr ',' '\n' | grep -E 'dbSize|leader|revision'

hr '4. 集群健康'
kubectl get nodes --no-headers
kubectl -n kube-system get pod -l component=etcd --no-headers

hr '5. 监听现状（永久修复确认）'
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | head -1 | sed 's|^node/||')
docker exec "$CP_NODE" grep -n 'listen-metrics-urls' /etc/kubernetes/manifests/etcd.yaml

hr '终验结束'
