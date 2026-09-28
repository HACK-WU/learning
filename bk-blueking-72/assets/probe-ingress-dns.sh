#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. ingress-nginx 的 svc 与对外端口 ====="
kubectl get svc -n ingress-nginx --no-headers 2>/dev/null | awk '{printf "  %-40s %-14s %-14s %s\n", $1, $2, $4, $5}'

echo ""
echo "===== 2. ingress-nginx Pod 所在节点（用于取节点 IP）====="
kubectl get pods -n ingress-nginx -o wide --no-headers 2>/dev/null | awk '{printf "  %-46s %-10s 节点=%s  PodIP=%s\n", $1, $3, $7, $6}'

echo ""
echo "===== 3. 节点 IP 清单 ====="
kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{printf "  %-20s %-14s %-10s 内网IP=%s\n", $1, $2, $3, $6}'

echo ""
echo "===== 4. 现有 Ingress 用了哪些域名 ====="
kubectl get ingress -n $NS --no-headers 2>/dev/null | awk '{print $3}' | tr ',' '\n' | sed 's/^ *//' | sort -u | sed 's/^/  /'

echo ""
echo "===== 5. coredns 当前配置（看有没有 hosts 插件）====="
kubectl get cm coredns -n kube-system -o yaml 2>/dev/null | sed -n '/Corefile/,/^kind/p' | head -40 | sed 's/^/  /'

echo ""
echo "===== 6. coredns Pod 状态 ====="
kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -i dns | awk '{printf "  %-46s %-12s 重启%s\n", $1, $3, $4}'

echo ""
echo "===== 7. 集群内所有 example.com 类占位域名（从 ConfigMap/Secret 里找）====="
kubectl get cm -n $NS -o jsonpath='{range .items[*]}{.data}{"\n"}{end}' 2>/dev/null \
  | grep -oE '[a-zA-Z0-9_-]+\.(paas|example|bktencent)\.[a-z]+' | sort -u | head -30 | sed 's/^/  /'
