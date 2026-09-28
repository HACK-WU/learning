#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== 1. ingress-nginx 网关暴露方式 ====="
kubectl get svc -n ingress-nginx --no-headers 2>/dev/null | sed 's/^/    /'

echo ""
echo "===== 2. 节点 IP（kind 节点即 WSL 内网络）====="
kubectl get nodes -o wide --no-headers 2>/dev/null | awk '{printf "    %-34s %-16s %s\n", $1, $6, $7}' | sed 's/^/  /'

echo ""
echo "===== 3. WSL 本机网卡地址 ====="
ip -4 addr show 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print "    "$2}' | sort -u

echo ""
echo "===== 4. 宿主机可达性：从 WSL 内试各入口 ====="
NP_HTTP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
echo "    HTTP NodePort = ${NP_HTTP:-未取到}"
for ip in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 -H "Host: bkpaas.paas.example.com" "http://$ip:$NP_HTTP/" 2>/dev/null)
  echo "    http://$ip:$NP_HTTP/  -> ${code:-不可达}"
done

echo ""
echo "===== 5. 全部 paas3 访问域名清单 ====="
kubectl get ingress -n $NS --no-headers 2>/dev/null | grep -E 'bkpaas3' | while read -r n h rest; do
  printf "    %-32s %s\n" "$h" "$n"
done

echo ""
echo "===== 6. 是否已有 LoadBalancer / 外部 IP ====="
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress}' 2>/dev/null | sed 's/^/    /'
echo ""
echo "===== 7. kind 集群端口映射（宿主机->容器）====="
docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep -iE 'control-plane|worker' | sed 's/^/    /'
