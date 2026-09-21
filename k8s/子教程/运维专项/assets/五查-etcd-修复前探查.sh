#!/usr/bin/env bash
# 修复前探查：改 0.0.0.0 后到底暴露给谁
# 安全声明：只读，不改任何资源
set -uo pipefail
hr() { printf '\n========== %s ==========\n' "$*"; }

CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o name | head -1 | sed 's|^node/||')
CP_CTR="$CP_NODE"
hr "控制面节点: $CP_NODE"

hr 'A. etcd Pod 是否 hostNetwork（决定暴露面大小）'
kubectl -n kube-system get pod -l component=etcd -o jsonpath='{range .items[*]}hostNetwork={.spec.hostNetwork}{"\n"}podIP={.status.podIP}{"\n"}{end}'

hr 'B. 节点 IP（若 hostNetwork，暴露面 = 节点 IP）'
kubectl get node "$CP_NODE" -o jsonpath='{.status.addresses[*].address}'
echo

hr 'C. 当前监听配置'
docker exec "$CP_CTR" grep -n 'listen-metrics-urls' /etc/kubernetes/manifests/etcd.yaml

hr 'D. 容器内当前实际监听的端口（改前基线）'
docker exec "$CP_CTR" sh -c 'command -v ss >/dev/null && ss -lntp 2>/dev/null | grep -E "2381|2379" || netstat -lntp 2>/dev/null | grep -E "2381|2379" || echo "(无 ss/netstat，跳过)"'

hr 'E. 备份是否还在'
docker exec "$CP_CTR" ls -l /tmp/etcd.yaml.orig 2>&1 | head -2

hr 'F. 现有 NetworkPolicy（判断能否用 netpol 收紧）'
kubectl get netpol -A --no-headers 2>/dev/null | head -20

hr 'G. monitoring 命名空间标签（netpol 选择器要用）'
kubectl get ns monitoring --show-labels

hr '探查结束'
