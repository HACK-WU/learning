#!/usr/bin/env bash
# etcd 指标与告警规则实测：验证「告警规则是活的还是死的」
# 安全声明：全部只读（查询 Prometheus API / 读配置），不修改任何资源
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

PROM_POD=$(kubectl -n monitoring get pod -o name 2>/dev/null | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
echo "prometheus pod: ${PROM_POD:-未找到}"

q() {
  # 在 prometheus 容器内用 wget 查 API，jq/grep 都不存在 → 只拿原始 JSON 片段
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
    "wget -qO- 'http://localhost:9090/api/v1/query?query=$1' 2>/dev/null" \
    | head -c 900
  echo
}

hr 'A. etcd 配额指标：到底有没有数据？'
echo '--- etcd_server_quota_backend_bytes ---'
q 'etcd_server_quota_backend_bytes'
echo
echo '--- etcd_mvcc_db_total_size_in_bytes ---'
q 'etcd_mvcc_db_total_size_in_bytes'

hr 'B. etcd 关键健康指标'
echo '--- etcd_server_has_leader ---'
q 'etcd_server_has_leader'
echo
echo '--- etcd_server_leader_changes_seen_total ---'
q 'etcd_server_leader_changes_seen_total'

hr 'C. 现有告警规则用了哪些 etcd 指标（决定规则是活是死）'
kubectl -n monitoring get prometheusrule kps-kube-prometheus-stack-etcd -o jsonpath='{.spec}' 2>/dev/null \
  | tr ',' '\n' \
  | grep -oE 'etcd_[a-z_]+' \
  | sort -u \
  | while read -r m; do printf '%s\n' "$m"; done

hr 'D. 实测结论所需：对照组（apiserver 指标有数据，证明采集链路本身是通的）'
echo '--- apiserver_request_total（应有大量数据）---'
q 'apiserver_request_total' | head -c 300
echo

hr 'E. 用 up 指标确认 etcd target 是否真的 UP'
q 'up{job="kube-etcd"}'

hr '查询结束'
