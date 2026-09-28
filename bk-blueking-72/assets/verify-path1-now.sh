#!/usr/bin/env bash
echo "===== 核验：路径1（apigateway->GSE）现在是否已经坏掉 ====="
echo ""
echo "--- 1. 先确认 GSE 只认块1 这个结论（回顾证据）---"
echo "  事实：块1=bk-gse,块2=ESB 时 -> migrate 403 x5"
echo "  事实：块1=ESB,  块2=bk-gse 时 -> migrate 403 x0"
echo "  推论：GSE 只读块1。那么用 bk-gse 私钥签的请求(路径1)现在应该失败"
echo ""

echo "--- 2. 找 values 源文件位置 ---"
for f in /root/bk-gse-values.backup.yaml /root/bk-gse-certs.backup.yaml; do
  [ -f "$f" ] && echo "  备份存在: $f ($(wc -c < $f) 字节)"
done
echo ""
echo "  搜索 bkapigateway_builtin_keypair.yaml:"
find /root /data /opt /home -name 'bkapigateway_builtin_keypair.yaml' 2>/dev/null | head -5 | sed 's/^/    /'
echo ""
echo "  搜索包含 bkApigatewayPublicKey 的 values 文件:"
grep -rl 'bkApigatewayPublicKey' /root /data /opt 2>/dev/null | head -5 | sed 's/^/    /'

echo ""
echo "--- 3. helm 里 bk-gse 的 release 与 chart 路径 ---"
helm list -n blueking 2>/dev/null | grep -E 'gse|NAME' | sed 's/^/  /'
echo ""
helm get values bk-gse -n blueking 2>/dev/null | head -30 | sed 's/^/  /'

echo ""
echo "--- 4. 检查 apigateway 里 bk-gse gateway 的 backend 健康 ---"
echo "  （若路径1已坏，调用方会报 403，但目前无调用方日志可证）"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse' | awk '{printf "  %-42s %-12s %s\n", $1, $2, $3}'
