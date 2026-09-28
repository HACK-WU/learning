#!/usr/bin/env bash
# 用途：部署前最后检查——storageClass、localpv、磁盘空间、命名空间
set -uo pipefail
B=/root/bk72/install/blueking

echo "===== 1. 集群 StorageClass（PVC 160Gi 能否落地）====="
kubectl get storageclass 2>&1 | head -10

echo ""
echo "===== 2. 是否有 localpv provisioner（官方用 hostDir /mnt/blueking）====="
kubectl get pods -A 2>/dev/null | grep -iE 'localpv|provisioner' | head -5
echo "(以上为空则需先部署 00-localpv)"

echo ""
echo "===== 3. 磁盘空间是否够 160Gi ====="
df -h / /mnt 2>/dev/null | head -5
echo "--- /mnt/blueking 是否存在 ---"
ls -ld /mnt/blueking 2>&1

echo ""
echo "===== 4. blueking 命名空间 ====="
kubectl get ns blueking 2>&1 | head -3

echo ""
echo "===== 5. 官方前置 helmfile（00-*）内容 ====="
for f in "$B"/00-*.yaml.gotmpl; do
  echo "--- $(basename "$f") ---"
  grep -E 'name:|chart:|condition:' "$f" | head -6
done

echo ""
echo "===== 6. localpv hostDir 配置 ====="
grep -nA5 'localpv:' "$B/environments/default/values.yaml" | head -10
