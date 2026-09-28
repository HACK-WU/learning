#!/usr/bin/env bash
echo "=== 1. 探测 hub.bktencent.com registry catalog ==="
timeout 30 curl -sS -k "https://hub.bktencent.com/v2/_catalog" 2>&1 | head -c 800
echo ""
echo ""
echo "=== 2. 探测常见蓝鲸镜像是否存在 ==="
for img in \
  "hub.bktencent.com/blueking/bk-cmdb:latest" \
  "hub.bktencent.com/blueking/bk-job:latest" \
  "hub.bktencent.com/blueking/blueking-paas:latest" \
  "hub.bktencent.com/blueking/bk-paas3:latest"; do
  code=$(timeout 20 curl -sS -o /dev/null -w "%{http_code}" -k "https://hub.bktencent.com/v2/${img#hub.bktencent.com/}/manifests/latest" 2>&1)
  echo "$img -> HTTP=$code"
done

echo ""
echo "=== 3. 实测拉取一个小镜像 (apigateway / nginx 类) ==="
for img in "hub.bktencent.com/blueking/nginx:latest" "hub.bktencent.com/blueking/bk-nginx:latest"; do
  echo "--- $img ---"
  timeout 120 docker pull "$img" >/tmp/p.log 2>&1 && echo "OK" || tail -2 /tmp/p.log
done
