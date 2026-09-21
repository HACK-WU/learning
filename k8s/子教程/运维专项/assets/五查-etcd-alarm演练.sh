#!/usr/bin/env bash
# ② etcd alarm 演练（可观测侧 · 全程只读）
#
# 为什么不做"真写满"：真写满 2Gi 会让集群进入 NOSPACE、拒绝所有写入，
#   恢复要 compact+defrag，且会污染用户的实训集群。代价远大于收益。
#   本脚本改为把「怎么发现 alarm、alarm 长什么样、怎么恢复」练到位。
#
# 安全声明（全部只读，不触发 alarm、不改数据）：
#   - alarm list / alarm disarm（无 alarm 时为 no-op，实测确认）
#   - 读启动参数、读指标、读 Prometheus 采集状态
#   - 不 compact、不 defrag、不写入任何 key、不重启组件
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

ETCD_POD=$(kubectl -n kube-system get pod -l component=etcd -o name | head -1 | sed 's|^pod/||')
echo "etcd pod: ${ETCD_POD:-未找到}"

ETCDCTL_ARGS="--endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
etcdctl_() { kubectl -n kube-system exec "$ETCD_POD" -- etcdctl $ETCDCTL_ARGS "$@"; }

hr 'A. quota 配在哪：启动参数'
kubectl -n kube-system get pod "$ETCD_POD" -o jsonpath='{.spec.containers[0].command}' \
  | tr ',' '\n' | grep -iE 'quota|backend|listen-metrics' \
  || echo '(无显式 --quota-backend-bytes → 用默认 2Gi = 2147483648 B)'

hr 'B. 容器内工具探测（决定指标怎么取）'
kubectl -n kube-system exec "$ETCD_POD" -- sh -c \
  'for c in wget curl etcdctl grep; do printf "%-10s %s\n" "$c" "$(command -v $c 2>/dev/null || echo MISSING)"; done' 2>&1

hr 'C. etcd /metrics 取数（grep 必须在容器外跑）'
echo '--- 路径：wget 在容器内，grep 在本机 ---'
kubectl -n kube-system exec "$ETCD_POD" -- sh -c \
  'wget -qO- --no-check-certificate \
     --certificate=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
     --private-key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
     --ca-certificate=/etc/kubernetes/pki/etcd/ca.crt \
     https://127.0.0.1:2379/metrics' 2>&1 \
  | grep -iE '^(etcd_server_quota_backend_bytes|etcd_db_total_size_in_bytes|etcd_mvcc_db_total_size_in_bytes)' \
  | head -10 \
  || echo '(该路径失败 → 见 D，用 etcdctl 替代)'

hr 'D. endpoint status：DB SIZE 有了，但 QUOTA 列不可信'
etcdctl_ endpoint status --write-out=table 2>&1 | head
echo
echo '--- JSON 里到底有没有 quota 字段 ---'
etcdctl_ endpoint status --write-out=json 2>/dev/null | head -c 800
echo
echo '>>> 注意 QUOTA 列：若显示 0 B，说明本版本 etcdctl 未上报该字段，'
echo '>>> 不能拿它当"配额还剩多少"的判据（详见讲义）。'

hr 'E. alarm 命令语义（健康集群上；disarm 无 alarm 时为 no-op）'
echo '$ etcdctl alarm list'
etcdctl_ alarm list 2>&1 | head
echo "   (空 = 无 alarm，健康)"
echo
echo '$ etcdctl alarm disarm  ← 无 alarm 时是 no-op，不会破坏任何东西'
etcdctl_ alarm disarm 2>&1 | head
echo "   (输出如上，证明该命令在无 alarm 时安全)"

hr 'F. 关键：etcd 到底有没有被 Prometheus 采集？'
echo '--- ServiceMonitor / scrape 配置 ---'
kubectl -n monitoring get servicemonitor -A 2>&1 | grep -iE 'NAME|etcd' | head
echo '--- Prometheus 里的 etcd target（用 up 指标反查）---'
PROM_POD=$(kubectl -n monitoring get pod -o name 2>/dev/null | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
echo "prometheus pod: ${PROM_POD:-未找到}"
if [ -n "$PROM_POD" ]; then
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
    'wget -qO- "http://localhost:9090/api/v1/query?query=up" 2>/dev/null' \
    | tr '}' '\n' | grep -ioE '"job":"[^"]*etcd[^"]*"' | sort -u | head \
    || echo '>>> Prometheus 里没有 etcd 相关 job'
fi

hr 'G. 告警规则里有没有 etcd 规则'
kubectl -n monitoring get prometheusrule -A 2>&1 | grep -iE 'NAME|etcd' | head

hr 'H. 碎片与配额占用（用 dbSize 与默认 2Gi 手算）'
etcdctl_ endpoint status --write-out=json 2>/dev/null \
  | sed -n 's/.*"dbSize":\([0-9]*\).*"dbSizeInUse":\([0-9]*\).*/\1 \2/p' \
  | while read -r total inuse; do
      if [ -n "$total" ]; then
        quota=2147483648
        printf 'dbSize        = %s B (%s MiB)\n' "$total" "$((total/1048576))"
        printf 'dbSizeInUse   = %s B (%s MiB)\n' "$inuse" "$((inuse/1048576))"
        printf '默认配额 2Gi  = %s B\n' "$quota"
        printf '占用配额      = %s%%\n' "$(( total * 100 / quota ))"
        printf '碎片率        = %s%%\n' "$(( (total - inuse) * 100 / total ))"
      fi
    done

hr '演练结束（集群状态未改变）'
