#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 方案 A 执行（第1步）：更新 GSE 证书，合并 bk-gse + ESB 两个公钥 ====="
echo ""

GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
echo "  GSE pod = $GP"

echo ""
echo "--- 1. 生成合并证书（原 bk-gse 公钥 + ESB 公钥）---"
# 当前 GSE 证书（bk-gse 公钥）
kubectl exec "$GP" -n blueking -c bk-gse-data -- cat /data/gse/cert/apigw_jwt.crt > /tmp/gse_cur.crt 2>/dev/null
# ESB 公钥
base64 -d /root/esb_pub.b64 > /tmp/esb_pub.pem 2>/dev/null

cat /tmp/gse_cur.crt > /tmp/combined.crt
printf '\n' >> /tmp/combined.crt
cat /tmp/esb_pub.pem >> /tmp/combined.crt

echo "  PEM 块数 = $(grep -c 'BEGIN' /tmp/combined.crt)"
echo "  块1(bk-gse) md5 = $(grep -v 'BEGIN\|END' /tmp/gse_cur.crt | tr -d '\n' | md5sum | awk '{print $1}')"
echo "  块2(ESB)   md5 = $(grep -v 'BEGIN\|END' /tmp/esb_pub.pem | tr -d '\n' | md5sum | awk '{print $1}')"

echo ""
echo "--- 2. 生成 patch JSON ---"
python3 -c '
import json
pem=open("/tmp/combined.crt").read()
patch={"data":{"apigw_jwt.crt":pem}}
open("/tmp/patch.json","w").write(json.dumps(patch))
print("  patch.json 已生成, PEM 字节数 =",len(pem))
'

echo ""
echo "--- 3. 应用 patch 到 ConfigMap ---"
kubectl patch configmap bk-gse-certs -n blueking --type merge --patch-file /tmp/patch.json 2>&1 | sed 's/^/  /'

echo ""
echo "--- 4. 重启 GSE 相关 deployment（让进程重读证书）---"
for d in $(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '{print $1}' | grep -E 'bk-gse'); do
  echo "  重启 $d"
  kubectl rollout restart deploy/"$d" -n blueking 2>&1 | sed 's/^/    /'
done

echo ""
echo "--- 5. 等待 GSE 就绪 ---"
for d in $(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '{print $1}' | grep -E 'bk-gse'); do
  kubectl rollout status deploy/"$d" -n blueking --timeout=180s 2>&1 | tail -1 | sed 's/^/    /'
done

echo ""
echo "--- 6. 验证：新 pod 里证书是否已更新 ---"
GP2=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP2" -n blueking -c bk-gse-data -- sh -c '
echo "  PEM 块数: $(grep -c BEGIN /data/gse/cert/apigw_jwt.crt)"
awk "/BEGIN/{n++} {print > (\"/tmp/blk\" n \".pem\")}" /data/gse/cert/apigw_jwt.crt 2>/dev/null
for f in /tmp/blk1.pem /tmp/blk2.pem; do
  [ -f "$f" ] && echo "  $f md5 = $(grep -v "BEGIN\|END" $f | tr -d "\n" | md5sum | awk "{print \$1}")"
done
' 2>&1 | sed 's/^/  /'
} > /root/apply-a.txt 2>&1
cat /root/apply-a.txt
