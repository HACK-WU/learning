#!/usr/bin/env bash
set -uo pipefail
OUT=/root/check-path1.txt
{
echo "===== 收尾核查：路径1（apigateway->GSE）是否被影响 ====="
echo ""

echo "--- 1. GSE 组件状态 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse' | awk '{print "  "$1"  "$2"  "$3}' | sed 's/^/  /'

echo ""
echo "--- 2. 节点管理（nodeman，走 GSE 的另一调用方）是否仍正常 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-nodeman' | awk '{print "  "$1"  "$2"  "$3}' | head -8

echo ""
echo "--- 3. 监控页面 Pod（之前卡 Init 的5个）是否起来 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'bk-monitor.*(web|page|grafana|api)' | awk '{print "  "$1"  "$2"  "$3}' | head -12

echo ""
echo "--- 4. 全集群未就绪 Pod 统计 ---"
echo "  总 Pod: $(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)"
echo "  未就绪: $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$2 !~ /^([0-9]+)\/\1$/ && $3 != "Completed" && $3 != "Succeeded" {print}' | wc -l)"
echo ""
echo "  未就绪明细(前10):"
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$2 !~ /^([0-9]+)\/\1$/ && $3 != "Completed" && $3 != "Succeeded" {print "    "$1"  "$2"  "$3}' | head -10

echo ""
echo "--- 5. 证书最终状态 ---"
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
awk "BEGIN{n=0} /BEGIN/{n++} {print > (\"/tmp/f\" n \".pem\")}" /data/gse/cert/apigw_jwt.crt 2>/dev/null
for f in /tmp/f1.pem /tmp/f2.pem; do
  [ -f "$f" ] && echo "  $(basename $f) md5 = $(grep -v "BEGIN\|END" $f | tr -d "\n" | md5sum | awk "{print \$1}")"
done
' 2>&1
} 2>&1 | tee "$OUT"
