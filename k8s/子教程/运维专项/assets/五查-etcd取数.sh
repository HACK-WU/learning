#!/usr/bin/env bash
# ② etcd 查：正确的取数路径（对比"取不到"的错误路径）
# 用途：证明 etcd 指标不在 apiserver 的 /metrics 里，必须走 etcd Pod 自己的 /metrics
# 安全声明：全部只读（get --raw / exec + wget 读指标），不修改任何资源
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
echo "etcd pod: ${ETCD_POD:-未找到}"

hr 'A. 错误路径：apiserver /metrics 里捞 etcd（捞不到）'
echo '$ kubectl get --raw /metrics | grep etcd_server_has_leader'
kubectl get --raw /metrics 2>/dev/null | grep -E '^etcd_server_has_leader' || echo '>>> 取不到（预期）：这些是 etcd 自身的指标，不在 apiserver 的 /metrics 里'

hr 'B. 正确路径一：etcd Pod 自带的 /metrics（2379 是 https，需证书）'
kubectl -n kube-system exec "$ETCD_POD" -- sh -c \
  'wget -qO- --no-check-certificate \
     --certificate=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
     --private-key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
     --ca-certificate=/etc/kubernetes/pki/etcd/ca.crt \
     https://127.0.0.1:2379/metrics 2>/dev/null | grep -E "^(etcd_server_has_leader|etcd_db_total_size_in_bytes|etcd_server_is_leader)"' \
  || echo '>>> 该路径失败（wget 可能未装于 distroless）'

hr 'C. 正确路径二：etcdctl endpoint status（含 leader / DB SIZE / raft index）'
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table 2>&1 | head

hr 'D. 正确路径三：etcdctl endpoint health（存活判定）'
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --write-out=table 2>&1 | head

hr 'E. 告警状态（etcd alarm，非空即异常）'
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  alarm list 2>&1 | head

hr 'F. 配额与碎片（DB SIZE vs 配额 2Gi）'
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=json 2>/dev/null | head -c 1200
echo

hr '取数结束'
