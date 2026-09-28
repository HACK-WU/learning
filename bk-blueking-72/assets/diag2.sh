#!/usr/bin/env bash
IMG="bk-lite.tencentcloudcr.com/bklite/bklite/fusion-collector:latest"

echo "=== 1. 该镜像 layer 数与总大小 (manifest) ==="
timeout 60 curl -sS -k "https://bk-lite.tencentcloudcr.com/v2/bklite/bklite/fusion-collector/manifests/latest" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" 2>&1 | head -c 1500

echo ""
echo ""
echo "=== 2. 是否有其他 tag ==="
timeout 60 curl -sS -k "https://bk-lite.tencentcloudcr.com/v2/bklite/bklite/fusion-collector/tags/list" 2>&1 | head -c 500

echo ""
echo ""
echo "=== 3. 已缓存 layer (content store) ==="
docker images -a --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep -i fusion || echo "(无)"

echo ""
echo "=== 4. 本地 docker 数据占用 ==="
docker system df 2>/dev/null | head -5
