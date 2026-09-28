#!/usr/bin/env bash
echo "=== 1. 官方下载页里的真实链接 ==="
timeout 30 curl -sS "https://bk.tencent.com/s-mart/downloads?type=packageDown&version=containerize" 2>&1 \
  | grep -oE 'https?://[a-zA-Z0-9./_-]*(bkopen|file\.myqcloud|cos\.)[a-zA-Z0-9./_-]*' | sort -u | head -10

echo ""
echo "=== 2. 尝试已知的蓝鲸文件站路径 ==="
for u in \
  "https://bkopen-1252002024.file.myqcloud.com/bkce7.2/" \
  "https://bkopen-1252002024.file.myqcloud.com/bk-install/" \
  "https://bkopen-1252002024.file.myqcloud.com/helm-charts/" ; do
  code=$(timeout 20 curl -sS -o /dev/null -w "%{http_code}" "$u" 2>&1)
  echo "$u -> $code"
done

echo ""
echo "=== 3. helm repo 正确路径探测 ==="
for ns in bkce blueking bkce7 bkce-cmdb bkbase; do
  code=$(timeout 20 curl -sS -o /dev/null -w "%{http_code}" -k "https://hub.bktencent.com/chartrepo/$ns/index.yaml" 2>&1)
  echo "chartrepo/$ns -> $code"
done

echo ""
echo "=== 4. GitHub 上的 7.2 部署脚本 (bk-install / bk-ce) ==="
timeout 20 curl -sS -o /dev/null -w "github TencentBlueKing HTTP=%{http_code}\n" https://github.com/TencentBlueKing 2>&1
