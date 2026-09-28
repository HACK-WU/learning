#!/usr/bin/env bash
IMG="bk-lite.tencentcloudcr.com/bklite/bklite/fusion-collector:latest"

echo "=== 1. 该镜像 layer 清单与大小 (从 registry 查询) ==="
timeout 120 docker pull "$IMG" 2>&1 | tail -12

echo ""
echo "=== 2. 已缓存的 layer 数 ==="
docker images -a | grep -c fusion || echo 0

echo ""
echo "=== 3. 是否可跳过: 该镜像在哪些 compose 文件被引用 ==="
grep -rn "FUSION_COLLECTOR" /tmp/bklite-src/compose/*.yaml | head -5
