#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 试拉 bkrepo 官方 init 镜像（几个候选名）====="
for IMG in \
  hub.bktencent.com/blueking/bkrepo-init:v3.3.1-beta.1 \
  hub.bktencent.com/blueking/bkrepo-init-mongodb:v3.3.1-beta.1 \
  hub.bktencent.com/blueking/bkrepo-init:latest ; do
  echo "  --- 探测 $IMG ---"
  kubectl delete pod imgprobe -n $NS --wait=false >/dev/null 2>&1
  sleep 1
  kubectl run imgprobe -n $NS --restart=Never --image=$IMG --command -- sh -c 'ls /data/workspace/ 2>&1; echo "---"; cat /data/workspace/init-mongodb.sh 2>/dev/null | head -40' 2>&1 | sed 's/^/    /'
  for i in $(seq 1 12); do
    S=$(kubectl get pod imgprobe -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
    [ "$S" = "Succeeded" ] || [ "$S" = "Failed" ] && break
    sleep 3
  done
  echo "    状态: $(kubectl get pod imgprobe -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)"
  echo "    输出:"
  kubectl logs imgprobe -n $NS 2>&1 | head -45 | sed 's/^/      /'
  echo ""
done
kubectl delete pod imgprobe -n $NS --wait=false >/dev/null 2>&1

echo "===== 2. 备选：从 github 官方仓库拿 init-mongodb.sh ====="
echo "  仓库: TencentBlueKing/bk-repo"
echo "  路径: support-files/kubernetes/charts/bkrepo/init-mongodb/ 或 scripts/"
