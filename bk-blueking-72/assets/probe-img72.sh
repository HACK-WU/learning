#!/usr/bin/env bash
echo "=== 1. 从 index.yaml 解析 bk-cmdb 的 chart 下载地址 ==="
timeout 30 curl -sS -k "https://hub.bktencent.com/chartrepo/blueking/index.yaml" -o /tmp/idx.yaml 2>&1
grep -A6 '^  bk-cmdb:' /tmp/idx.yaml | grep -E 'urls|version' | head -6

echo ""
echo "=== 2. 下载 chart 并解压 ==="
cd /tmp && rm -rf cmdbchart && mkdir -p cmdbchart && cd cmdbchart
URLS=$(grep -A6 '^  bk-cmdb:' /tmp/idx.yaml | grep -oE 'chartrepo/blueking/charts/[^ ]+tgz' | head -1)
echo "chart url: $URLS"
timeout 90 curl -sS -k -O "https://hub.bktencent.com/$URLS" 2>&1 && ls -la *.tgz 2>/dev/null \
  && tar xzf *.tgz && echo "解压 OK" || echo "下载失败"

echo ""
echo "=== 3. chart 内真实镜像定义 ==="
if ls bk-cmdb/values.yaml >/dev/null 2>&1; then
  grep -rhoE '(repository|image): *[^ ]+' bk-cmdb/values.yaml | sort -u | head -10
fi
