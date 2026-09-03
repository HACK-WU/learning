#!/bin/bash
# 课 8：拉取集群三件套镜像（三个独立仓库，tag 带 -cluster 后缀）
VER="${1:-v1.151.0-cluster}"

echo "=============================================="
echo " 拉取 $VER 三件套"
echo "=============================================="
for c in vmstorage vminsert vmselect; do
  echo "-- victoriametrics/$c:$VER --"
  timeout 300 docker pull "victoriametrics/$c:$VER" 2>&1 | tail -2
done

echo
echo "=============================================="
echo " 校验：镜像内容与版本"
echo "=============================================="
docker images 2>&1 | grep -E 'victoriametrics|REPOSITORY'

echo
echo "=============================================="
echo " 组件版本自证"
echo "=============================================="
for c in vmstorage vminsert vmselect; do
  echo -n "  $c: "
  docker run --rm "victoriametrics/$c:$VER" --version 2>&1 | head -1
done
