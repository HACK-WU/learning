#!/usr/bin/env bash
echo "===== 收尾核查 ====="
echo ""
echo "--- 1. GSE 组件状态 ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep bk-gse | awk '{printf "  %-42s %-12s %s\n", $1, $2, $3}'

echo ""
echo "--- 2. 节点管理（另一个 GSE 调用方）---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep bk-nodeman | awk '{printf "  %-42s %-12s %s\n", $1, $2, $3}' | head -8

echo ""
echo "--- 3. 监控页面 Pod（之前卡 Init 的）---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep bk-monitor | grep -iE 'web|page|grafana' | awk '{printf "  %-42s %-12s %s\n", $1, $2, $3}' | head -10

echo ""
echo "--- 4. 集群整体 ---"
TOTAL=$(kubectl get pods -n blueking --no-headers 2>/dev/null | wc -l)
echo "  总 Pod: $TOTAL"
echo "  未就绪明细:"
kubectl get pods -n blueking --no-headers 2>/dev/null | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded" {printf "    %-40s %-12s %s\n", $1, $2, $3}' | head -12

echo ""
echo "--- 5. 证书最终状态 ---"
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep bk-gse-data- | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c 'awk "BEGIN{n=0} /BEGIN/{n++} {print > (\"/tmp/f\" n \".pem\")}" /data/gse/cert/apigw_jwt.crt; for f in /tmp/f1.pem /tmp/f2.pem; do [ -f "$f" ] && echo "  $(basename $f) md5 = $(grep -v BEGIN $f | grep -v END | tr -d "\n" | md5sum | cut -d" " -f1)"; done'
