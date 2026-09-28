#!/usr/bin/env bash
set -uo pipefail
BK=/root/bk72/install/blueking
cd "$BK" || exit 1
export HELMFILE=/root/bk72/install/bin/helmfile

{
echo "===== 安装 bk-nodeman 节点管理 ====="
echo "开始: $(date '+%F %T')"

timeout 2400 $HELMFILE -f base-blueking.yaml.gotmpl -l seq=fifth sync 2>&1 | tail -50

echo ""
echo "结束: $(date '+%F %T')"
echo "helmsync exit=$?"

echo ""
echo "===== 结果检查 ====="
helm list -A --short 2>/dev/null | grep -E 'nodeman' | sed 's/^/  /' || echo "  (nodeman release 未创建)"
echo ""
echo "--- nodeman Pod ---"
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -i 'nodeman' | sed 's/^/  /' || echo "  (无 nodeman Pod)"
echo ""
echo "--- nodeman Service/Ingress ---"
kubectl get svc -n blueking --no-headers 2>/dev/null | grep -i 'nodeman' | sed 's/^/  /'
kubectl get ingress -n blueking --no-headers 2>/dev/null | grep -i 'nodeman' | sed 's/^/  /'
} > /root/nodeman-install.txt 2>&1
cat /root/nodeman-install.txt
