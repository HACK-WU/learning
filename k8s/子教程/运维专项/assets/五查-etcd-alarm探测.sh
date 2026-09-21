#!/usr/bin/env bash
# etcd alarm 演练 · 前置探测（只读）
# 目标：搞清楚 quota 配在哪、指标叫什么、有没有现成镜像可用来做"真写满"演练
# 安全声明：全部只读（get / exec 读指标 / docker images），不创建、不修改、不删除任何资源
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
echo "etcd pod: ${ETCD_POD:-未找到}"

hr 'A. quota 配在哪：etcd 启动参数'
kubectl -n kube-system get pod "$ETCD_POD" -o jsonpath='{.spec.containers[0].command}' \
  | tr ',' '\n' | grep -iE 'quota|backend' || echo '(未见显式 quota 参数 → 用默认 2Gi)'

hr 'B. quota 相关指标（关键：grep 必须在容器外跑）'
echo '--- 正确写法：wget 在容器内，grep 在容器外 ---'
kubectl -n kube-system exec "$ETCD_POD" -- sh -c \
  'wget -qO- --no-check-certificate \
     --certificate=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
     --private-key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
     --ca-certificate=/etc/kubernetes/pki/etcd/ca.crt \
     https://127.0.0.1:2379/metrics' 2>/dev/null \
  | grep -E '^(etcd_server_quota_backend_bytes|etcd_db_total_size_in_bytes|etcd_mvcc_db_total_size_in_bytes)' \
  || echo '(仍取不到，见 C)'

hr 'C. 备选：etcdctl endpoint status 里的 quota 列'
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table 2>&1 | head

hr 'D. 当前 alarm（空 = 健康）'
kubectl -n kube-system exec "$ETCD_POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  alarm list 2>&1 | head
echo "(以上为空即当前无 alarm)"

hr 'E. 本地是否已有 etcd 镜像（决定能否起临时容器而不拉镜像）'
docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -i etcd | head
echo '--- kind 节点用的 etcd 镜像 ---'
docker inspect "$(docker ps --format '{{.Names}}' | grep etcd | head -1)" \
  --format '{{.Config.Image}}' 2>/dev/null || echo '(未找到 etcd 容器)'

hr 'F. 磁盘余量（评估"真写满"演练的可行性）'
df -h /var/lib/docker 2>/dev/null | tail -2 || df -h / | tail -2

hr '探测结束'
