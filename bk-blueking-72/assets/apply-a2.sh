#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 方案 A 第2步：ESB 公钥放到块1（原方案A的真意）====="
echo "  块1 = ESB 公钥 (0e82d670)   <- 修复路径2"
echo "  块2 = bk-gse 公钥 (0e18be8a) <- 尽量保留路径1"
echo ""

echo "--- 1. 构造新证书（ESB 在前）---"
base64 -d /root/esb_pub.b64 > /tmp/esb_pub.pem 2>/dev/null
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP" -n blueking -c bk-gse-data -- cat /data/gse/cert/apigw_jwt.crt > /tmp/gse_cur.crt 2>/dev/null

# 从当前2块证书里提取 bk-gse 那块（块1）
awk 'BEGIN{n=0} /BEGIN/{n++} {print > ("/tmp/old_blk" n ".pem")}' /tmp/gse_cur.crt 2>/dev/null

cat /tmp/esb_pub.pem > /tmp/new.crt
printf '\n' >> /tmp/new.crt
cat /tmp/old_blk1.pem >> /tmp/new.crt

echo "  新块1(ESB)   md5 = $(grep -v 'BEGIN\|END' /tmp/esb_pub.pem | tr -d '\n' | md5sum | awk '{print $1}')"
echo "  新块2(bk-gse) md5 = $(grep -v 'BEGIN\|END' /tmp/old_blk1.pem | tr -d '\n' | md5sum | awk '{print $1}')"
echo "  PEM 块数 = $(grep -c 'BEGIN' /tmp/new.crt)"

echo ""
echo "--- 2. 应用到 ConfigMap ---"
python3 -c '
import json
pem=open("/tmp/new.crt").read()
json.dump({"data":{"apigw_jwt.crt":pem}}, open("/tmp/patch2.json","w"))
print("  patch2.json 已生成")
' 2>&1 | sed 's/^/  /'

kubectl patch configmap bk-gse-certs -n blueking --type merge --patch-file /tmp/patch2.json 2>&1 | sed 's/^/  /'

echo ""
echo "--- 3. 重启 GSE ---"
for d in $(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '{print $1}' | grep -E 'bk-gse'); do
  kubectl rollout restart deploy/"$d" -n blueking 2>&1 | sed 's/^/    /'
done

for d in $(kubectl get deploy -n blueking --no-headers 2>/dev/null | awk '{print $1}' | grep -E 'bk-gse'); do
  kubectl rollout status deploy/"$d" -n blueking --timeout=180s 2>&1 | tail -1 | sed 's/^/    /'
done

echo ""
echo "--- 4. 验证证书顺序 ---"
GP2=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
kubectl exec "$GP2" -n blueking -c bk-gse-data -- sh -c '
awk "BEGIN{n=0} /BEGIN/{n++} {print > (\"/tmp/n\" n \".pem\")}" /data/gse/cert/apigw_jwt.crt 2>/dev/null
for f in /tmp/n1.pem /tmp/n2.pem; do
  [ -f "$f" ] && echo "  $(basename $f) md5 = $(grep -v "BEGIN\|END" $f | tr -d "\n" | md5sum | awk "{print \$1}")"
done
' 2>&1 | sed 's/^/  /'

echo ""
echo "--- 5. 重跑 migrate 验证 ---"
kubectl delete job bk-monitor-migrate-2 -n blueking --wait=false 2>&1 | sed 's/^/  /'
sleep 5
kubectl apply -f /root/bk-monitor-migrate-2.clean.yaml 2>&1 | sed 's/^/  /'
sleep 60
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
echo "  新 pod = $MPOD  状态=$(kubectl get pod $MPOD -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)"
echo "  403 次数 = $(kubectl logs $MPOD -n blueking --all-containers 2>/dev/null | grep -icE '403')"
echo ""
echo "  --- 最后 12 行 ---"
kubectl logs "$MPOD" -n blueking --all-containers --tail=12 2>/dev/null | cut -c1-200 | sed 's/^/    /'
} > /root/apply-a2.txt 2>&1
cat /root/apply-a2.txt
