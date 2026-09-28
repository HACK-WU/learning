#!/usr/bin/env bash
# 用途：镜像可达性实测——用 registry HTTP API 直连（不依赖 docker）
# 目标：判定 hub.bktencent.com 是否匿名可拉
set -uo pipefail
R=hub.bktencent.com
IMGS=(
  "bitnami/mysql:8.0.37-debian-12-r2"
  "bitnami/redis:6.2.7-debian-11-r11"
  "bitnami/mongodb:4.4.10-debian-10-r44"
)

echo "===== 0. 网络连通性 ====="
curl -s -o /dev/null -w "HTTPS 根路径: %{http_code} (耗时 %{time_total}s)\n" --max-time 15 "https://$R/" 2>&1

echo ""
echo "===== 1. Docker Registry v2 API 探测（匿名）====="
for img in "${IMGS[@]}"; do
  repo="${img%%:*}"
  tag="${img##*:}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 \
    "https://$R/v2/$repo/manifests/$tag" 2>&1)
  echo "$repo:$tag -> HTTP $code"
done

echo ""
echo "===== 2. 无认证时的 WWW-Authenticate 头（判断是否需授权）====="
curl -s -I --max-time 20 "https://$R/v2/" 2>&1 | grep -iE 'www-authenticate|HTTP/' | head -5

echo ""
echo "===== 3. 结论判定 ====="
echo "HTTP 200 = 匿名可拉；401/403 = 需授权；404 = 路径错误"
