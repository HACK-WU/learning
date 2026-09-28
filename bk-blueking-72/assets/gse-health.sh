#!/usr/bin/env bash
set -uo pipefail
{
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)

echo "===== 1. GSE data 服务健康状态（最关键）====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
  echo "  --- 进程 ---"
  ps aux 2>/dev/null | grep -i gse | grep -v grep | head -8
  echo "  --- 本地回环自测 59702 ---"
  wget -S -O- -m 5 "http://127.0.0.1:59702/" 2>&1 | head -6
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. GSE 相关所有 Pod 状态 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse' | sed 's/^/  /'

echo ""
echo "===== 3. GSE 依赖的 zookeeper/其他是否就绪 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'zookeeper|zk' | sed 's/^/  /' | head -6

echo ""
echo "===== 4. GSE data 日志（全部，找真实状态）====="
kubectl logs "$GP" -n blueking -c bk-gse-data --tail=60 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 5. 关键：GSE 的 403 是不是"未就绪"的表现 ====="
echo "  证据：不带任何认证头 -> 403"
echo "  证据：带 ESB 的 app_code/secret -> 403 invalid signature"
echo "  --> 两种都 403，说明不是鉴权逻辑问题"
echo "  --> 更可能是 GSE 服务未完全就绪，对所有请求统一 403"

echo ""
echo "===== 6. 对比：GSE 其他端口是否也一样 ====="
kubectl delete pod gseprobe -n blueking --ignore-not-found --wait=false 2>/dev/null
kubectl run gseprobe -n blueking --image=hub.bktencent.com/library/busybox:1.34.0 --restart=Never --command -- sleep 300 2>&1 | tail -1
for i in $(seq 1 30); do
  [ "$(kubectl get pod gseprobe -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" ] && break
  sleep 2
done
kubectl exec gseprobe -n blueking -- sh -c '
  for p in 59702 58625 28625 29402; do
    echo -n "  端口 $p: "
    wget -S -O- -m 5 "http://bk-gse-data:$p/" 2>&1 | grep -oE "HTTP/1.1 [0-9]+.*" | head -1
  done
' 2>&1 | sed 's/^/  /'
kubectl delete pod gseprobe -n blueking --ignore-not-found --wait=false 2>&1 | sed 's/^/  /'
} > /root/gse-health.txt 2>&1
cat /root/gse-health.txt
