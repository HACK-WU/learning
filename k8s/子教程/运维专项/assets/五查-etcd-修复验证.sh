#!/usr/bin/env bash
# 修复后验证：告警规则的分子分母是否可算、其他 etcd 指标是否复活
# 安全声明：只读查询 Prometheus，不改任何资源
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

PROM_POD=$(kubectl -n monitoring get pod -o name | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
q() {
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
    "wget -qO- 'http://localhost:9090/api/v1/query?query=$1' 2>/dev/null" | head -c 600
  echo
}

hr 'A. 占用率 = db_total_size / quota_backend_bytes（告警规则该盯的数）'
q '(etcd_mvcc_db_total_size_in_bytes/etcd_server_quota_backend_bytes)*100'

hr 'B. 其他 etcd 告警指标是否也复活了'
echo '--- etcd_server_proposals_failed_total ---'
q 'etcd_server_proposals_failed_total'
echo
echo '--- etcd_server_leader_changes_seen_total ---'
q 'etcd_server_leader_changes_seen_total'
echo
echo '--- etcd_mvcc_db_total_size_in_use_in_bytes ---'
q 'etcd_mvcc_db_total_size_in_use_in_bytes'

hr 'C. 磁盘/网络类指标（告警规则同样引用）'
echo '--- etcd_network_peer_sent_failures_total ---'
q 'etcd_network_peer_sent_failures_total'
echo
echo '--- etcd_disk_wal_fsync_duration_seconds_bucket ---'
q 'etcd_disk_wal_fsync_duration_seconds_bucket' | head -c 400

hr 'D. 与 etcdctl 交叉验证（指标口径 vs etcdctl 口径是否一致）'
ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=json 2>/dev/null | head -c 500
echo
echo '>>> 对比：指标 etcd_mvcc_db_total_size_in_bytes 应 ≈ etcdctl 的 dbSize'

hr '验证结束'
