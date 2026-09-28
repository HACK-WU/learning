#!/usr/bin/env bash
set -uo pipefail
{
SECRET_MON=$(grep 'bk_monitorv3:' /root/bk72/install/blueking/environments/default/app_secret.yaml | awk '{print $2}')
SECRET_GSE=$(grep 'bk_gse:' /root/bk72/install/blueking/environments/default/app_secret.yaml | awk '{print $2}')

echo "===== 1. 起临时 Pod 复现（用 busybox + curl）====="
kubectl delete pod curl403 -n blueking --ignore-not-found --wait=false 2>/dev/null
kubectl run curl403 -n blueking --image=hub.bktencent.com/library/busybox:1.34.0 --restart=Never \
  --command -- sleep 900 2>&1 | tail -1
for i in $(seq 1 30); do
  S=$(kubectl get pod curl403 -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Running" ] && break
  sleep 2
done
echo "  临时Pod状态: $(kubectl get pod curl403 -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)"

echo ""
echo "===== 2. 带 bk_monitorv3 认证头调 GSE 网关接口 ====="
BASE="http://bkapi.paas.example.com/api/bk-gse/prod"
for ACT in config_query_streamto config_add_streamto; do
  echo "  --- $ACT ---"
  kubectl exec curl403 -n blueking -- sh -c "
    wget -q -O- --header='X-Bk-App-Code: bk_monitorv3' \
      --header='X-Bk-App-Secret: ${SECRET_MON}' \
      --header='Content-Type: application/json' \
      '${BASE}/${ACT}/' 2>&1 | head -c 400
    echo ''
  " 2>&1 | sed 's/^/    /'
done

echo ""
echo "===== 3. 不带认证头（对照：看是否也是403）====="
kubectl exec curl403 -n blueking -- sh -c "
  wget -S -O- '${BASE}/config_query_streamto/' 2>&1 | grep -iE 'HTTP/|403|401' | head -5
  echo ''
" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. 用 gse 自己的 secret 调（对照）====="
kubectl exec curl403 -n blueking -- sh -c "
  wget -q -O- --header='X-Bk-App-Code: bk_gse' --header='X-Bk-App-Secret: ${SECRET_GSE}' \
    '${BASE}/config_query_streamto/' 2>&1 | head -c 300
  echo ''
" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 直连 GSE 后端（绕过网关）====="
kubectl exec curl403 -n blueking -- sh -c "
  for u in http://bk-gse-admin:59629/ http://bk-gse-cluster:59313/; do
    echo \"  URL=\$u\"
    wget -S -O- \"\$u\" 2>&1 | grep -iE 'HTTP/' | head -2
  done
" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 6. 清理 ====="
kubectl delete pod curl403 -n blueking --ignore-not-found --wait=false 2>&1 | sed 's/^/  /'
} > /root/repro-403.txt 2>&1
cat /root/repro-403.txt
