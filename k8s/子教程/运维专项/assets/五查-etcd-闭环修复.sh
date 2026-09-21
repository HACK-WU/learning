#!/usr/bin/env bash
# etcd 监控静默失效：闭环验证（在 kind 控制面上改监听地址，验证后立即还原）
#
# ⚠️ 本脚本会修改控制面节点上的 etcd 静态清单（/etc/kubernetes/manifests/etcd.yaml）
#    属「改环境」操作，仅在用户明确授权后运行；脚本内建 --restore 用于还原。
#
# 设计：
#   - fix    ：把 --listen-metrics-urls 从 http://127.0.0.1:2381 改为 http://0.0.0.0:2381
#   - check  ：验证 Prometheus 能否抓到 etcd 指标
#   - restore：把清单改回 127.0.0.1:2381（幂等，可反复执行）
#
# 风险边界：
#   - 只改 --listen-metrics-urls 一行；不动 2379 数据端口、不动证书、不动集群配置
#   - kubelet 会自动重启 etcd Pod（静态清单机制），期间 apiserver 短暂不可用（秒级）
#   - 不执行 compact/defrag，不写任何业务数据
set -uo pipefail

hr() { printf '\n========== %s ==========\n' "$*"; }

CP=$(docker ps --format '{{.Names}}' 2>/dev/null | grep control-plane | head -1)
MANIFEST=/etc/kubernetes/manifests/etcd.yaml
BACKUP=/tmp/etcd.yaml.orig
echo "控制面容器: ${CP:-未找到}"

PROM_POD=$(kubectl -n monitoring get pod -o name | grep 'prometheus-kps' | head -1 | sed 's|^pod/||')
q() {
  kubectl -n monitoring exec "$PROM_POD" -c prometheus -- sh -c \
    "wget -qO- 'http://localhost:9090/api/v1/query?query=$1' 2>/dev/null" | head -c 700
  echo
}

fix() {
  hr '0. 备份原清单（若已备份则跳过，保证幂等）'
  docker exec "$CP" sh -c "[ -f $BACKUP ] || cp $MANIFEST $BACKUP; ls -la $BACKUP"

  hr '1. 改前状态：确认监听地址与 up=0'
  docker exec "$CP" grep -n 'listen-metrics-urls' "$MANIFEST"
  echo '--- up ---'
  q 'up{job="kube-etcd"}'

  hr '2. 修改：127.0.0.1:2381 → 0.0.0.0:2381'
  docker exec "$CP" sed -i 's|--listen-metrics-urls=http://127.0.0.1:2381|--listen-metrics-urls=http://0.0.0.0:2381|' "$MANIFEST"
  docker exec "$CP" grep -n 'listen-metrics-urls' "$MANIFEST"

  hr '3. 等 kubelet 重建 etcd Pod（静态清单机制，约 10~40 秒）'
  for i in $(seq 1 12); do
    sleep 5
    st=$(kubectl -n kube-system get pod -l component=etcd --no-headers 2>/dev/null | awk '{print $3}')
    echo "  [$((i*5))s] etcd pod: ${st:-不存在}"
    [ "$st" = "Running" ] && break
  done

  hr '4. 等 Prometheus 抓取（抓取间隔通常 30s，等 2 轮）'
  sleep 65

  hr '5. 验证：up 是否变 1'
  q 'up{job="kube-etcd"}'

  hr '6. 验证：etcd 指标是否有数据（修复前全是空）'
  echo '--- etcd_server_has_leader ---'
  q 'etcd_server_has_leader'
  echo
  echo '--- etcd_mvcc_db_total_size_in_bytes ---'
  q 'etcd_mvcc_db_total_size_in_bytes'
  echo
  echo '--- etcd_server_quota_backend_bytes（告警规则的分子分母）---'
  q 'etcd_server_quota_backend_bytes'
}

check() {
  hr '当前监听地址'
  docker exec "$CP" grep -n 'listen-metrics-urls' "$MANIFEST"
  hr 'up 与关键指标'
  q 'up{job="kube-etcd"}'
  echo '--- etcd_server_has_leader ---'
  q 'etcd_server_has_leader'
  echo '--- etcd_server_quota_backend_bytes ---'
  q 'etcd_server_quota_backend_bytes'
}

restore() {
  hr '还原：0.0.0.0:2381 → 127.0.0.1:2381'
  if docker exec "$CP" sh -c "[ -f $BACKUP ]"; then
    docker exec "$CP" cp "$BACKUP" "$MANIFEST"
    echo "已从 $BACKUP 还原"
  else
    docker exec "$CP" sed -i 's|--listen-metrics-urls=http://0.0.0.0:2381|--listen-metrics-urls=http://127.0.0.1:2381|' "$MANIFEST"
    echo "已用 sed 反向替换还原"
  fi
  docker exec "$CP" grep -n 'listen-metrics-urls' "$MANIFEST"

  hr '等 kubelet 重建 etcd Pod'
  for i in $(seq 1 12); do
    sleep 5
    st=$(kubectl -n kube-system get pod -l component=etcd --no-headers 2>/dev/null | awk '{print $3}')
    echo "  [$((i*5))s] etcd pod: ${st:-不存在}"
    [ "$st" = "Running" ] && break
  done

  hr '确认集群健康'
  kubectl get nodes --no-headers 2>&1 | head -3
  kubectl -n kube-system get pod -l component=etcd --no-headers 2>&1 | head -2
  hr '还原完成（up 会重新变回 0，这是预期：说明我们验证的是因果关系）'
  q 'up{job="kube-etcd"}'
}

case "${1:-check}" in
  fix)     fix     ;;
  check)   check   ;;
  restore) restore ;;
  *) echo "用法: $0 {fix|check|restore}" ;;
esac
