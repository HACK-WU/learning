#!/usr/bin/env bash
set -uo pipefail
{
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 403 仍在，排查合并公钥为何未生效 ====="
echo ""

echo "--- 1. migrate 新日志里的 403 明细 ---"
kubectl logs "$MPOD" -n blueking --all-containers 2>/dev/null | grep -iE '403|invalid signature|streamto' | tail -8 | cut -c1-260 | sed 's/^/  /'

echo ""
echo "--- 2. GSE 侧日志（是否仍 invalid signature）---"
kubectl logs "$GP" -n blueking -c bk-gse-data --tail=300 2>/dev/null | grep -iE 'jwt|signature|403|verify|cert' | tail -12 | cut -c1-220 | sed 's/^/  /'

echo ""
echo "--- 3. GSE 证书当前内容（确认 2 块都在）---"
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c 'grep -c BEGIN /data/gse/cert/apigw_jwt.crt' 2>&1 | sed 's/^/  PEM块数: /'

echo ""
echo "--- 4. 关键推断：GSE 可能只读第一个 PEM 块 ---"
echo "  若只读块1(bk-gse=0e18be8a)，则 ESB 签的仍失败 -> 需改成块1=ESB"
echo "  但那样会打坏路径1的41个resource"

echo ""
echo "--- 5. 验证：GSE 是否支持多公钥（看它日志里是否报 cert 加载数量）---"
kubectl logs "$GP" -n blueking -c bk-gse-data --tail=500 2>/dev/null | grep -iE 'load|cert|public.*key|init' | tail -10 | cut -c1-200 | sed 's/^/  /'

echo ""
echo "--- 6. 备选：证书除了 apigw_jwt.crt，还有别的文件吗 ---"
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c 'ls -la /data/gse/cert/' 2>&1 | sed 's/^/  /'
} > /root/why-still.txt 2>&1
cat /root/why-still.txt
} > /root/why-still.txt 2>&1
cat /root/why-still.txt
