#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 用 helmfile 渲染出 bk-gse 实际拿到的 publicKey 并比对 ====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
GSE_BODY=$(kubectl exec "$GP" -n blueking -- sh -c 'grep -v "BEGIN\|END" /data/gse/cert/apigw_jwt.crt | tr -d "\n"' 2>/dev/null)
GSE_MD5=$(echo -n "$GSE_BODY" | md5sum | awk '{print $1}')
echo "  GSE 容器内证书 md5 = $GSE_MD5"

echo ""
echo "  --- 配置文件里所有 publicKeyBase64 解码后 md5 ---"
grep 'publicKeyBase64' /root/bk72/install/blueking/environments/default/bkapigateway_builtin_keypair.yaml 2>/dev/null | \
while IFS= read -r line; do
  B64=$(echo "$line" | sed 's/.*publicKeyBase64: *//' | tr -d ' \r')
  MD5=$(echo -n "$B64" | base64 -d 2>/dev/null | grep -v 'BEGIN\|END' | tr -d '\n' | md5sum | awk '{print $1}')
  if [ "$MD5" = "$GSE_MD5" ]; then
    echo "    [匹配] $MD5  <== 这就是配给 GSE 的公钥"
  else
    echo "    [不同] $MD5"
  fi
done

echo ""
echo "  --- 上面有哪些 gateway 名 ---"
grep -B1 'publicKeyBase64' /root/bk72/install/blueking/environments/default/bkapigateway_builtin_keypair.yaml 2>/dev/null | grep -v 'publicKeyBase64' | grep -v '^--' | sed 's/^/    /'

echo ""
echo "===== 结论 ====="
echo "  若上面出现 [匹配]：GSE 用的就是配置源里的公钥，说明"
echo "  问题在于 apigateway 实际签发 JWT 用的是另一把私钥（core_jwt 表里的），"
echo "  与这个预置公钥不是一对 —— 即密钥对错配。"
echo ""
echo "  core_jwt 表里的 5 个 public_key md5（apigateway 实际在用）："
echo "    ca2e07c4b820377a0c439fd270bfc676"
echo "    771ea1d0d5b9df08c6fcffa1198c4b66 (x2)"
echo "    db2bbf5a6a1cf64cffffc6591d0a90b3"
echo "    72f5d8ef9e2745869764e94bb21f60a9"
echo "  GSE 用的: $GSE_MD5"
echo "  --> 只要上述 5 个里没有 $GSE_MD5，即为密钥错配，坐实根因。"
} > /root/jwt-conclude.txt 2>&1
cat /root/jwt-conclude.txt
