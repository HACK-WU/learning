#!/usr/bin/env bash
# 用途：测试能否用「匿名 token」换取拉取权限（Harbor 常见开放模式）
set -uo pipefail
R=hub.bktencent.com

echo "===== 1. 尝试匿名换取 token ====="
TOK=$(curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:bitnami/mysql:pull" 2>&1)
echo "响应: $(echo "$TOK" | head -c 300)"

echo ""
echo "===== 2. 若拿到 token，用它再请求 manifest ====="
T=$(echo "$TOK" | grep -oE '"token":"[^"]+"' | sed 's/"token":"//; s/"$//' | head -1)
if [ -n "$T" ]; then
  echo "已获取 token (长度 ${#T})"
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 \
    -H "Authorization: Bearer $T" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "https://$R/v2/bitnami/mysql/manifests/8.0.37-debian-12-r2")
  echo "带 token 请求 manifest -> HTTP $code"
else
  echo "未拿到 token"
fi

echo ""
echo "===== 3. 探测 Harbor 是否开放 public 项目列表 ====="
curl -s --max-time 20 "https://$R/api/v2.0/projects?page=1&page_size=5" 2>&1 | head -c 300
echo ""
echo "HTTP code: $(curl -s -o /dev/null -w '%{http_code}' --max-time 20 'https://'$R'/api/v2.0/projects?page=1&page_size=5')"

echo ""
echo "===== 4. 对照：Docker Hub 官方源是否可达（替代方案可行性）====="
curl -s -o /dev/null -w "docker.io/bitnami/mysql: %{http_code} (%{time_total}s)\n" --max-time 20 \
  "https://registry-1.docker.io/v2/bitnami/mysql/manifests/8.0.37-debian-12-r2" 2>&1
