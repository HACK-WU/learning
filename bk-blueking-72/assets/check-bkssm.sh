#!/usr/bin/env bash
set -uo pipefail
# 用已有凭据探测 registry
TOKEN=$(curl -s -u 'blueking:blueking' \
  'https://hub.bktencent.com/service/token?scope=repository:blueking/bkssm:pull&service=harbor-registry' \
  | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
echo "token 长度: ${#TOKEN}"
[ -z "$TOKEN" ] && { echo "取 token 失败"; exit 1; }

echo ""
echo "===== 1. bkssm:v1.0.12 manifest 是否存在 ====="
curl -s -o /dev/null -w "  HTTP %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://hub.bktencent.com/v2/blueking/bkssm/manifests/v1.0.12"

echo ""
echo "===== 2. 该仓库有哪些 tag ====="
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://hub.bktencent.com/v2/blueking/bkssm/tags/list" | tr ',' '\n' | grep -o '"v\?[0-9][^"]*"' | sort -u | sed 's/^/    /'

echo ""
echo "===== 3. 对照：bkiam 是否存在（已知 worker 上有）====="
curl -s -o /dev/null -w "  HTTP %{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://hub.bktencent.com/v2/blueking/bkiam/manifests/v1.12.21"
