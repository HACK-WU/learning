#!/usr/bin/env bash
# 诊断：blob 下载到底发生了什么（重定向？还是被拒？）
set -uo pipefail
REG=hub.bktencent.com
REPO=bitnami/elasticsearch
TAG=7.16.2-debian-10-r0

REALM="https://hub.bktencent.com/service/token"
SCOPE="repository:${REPO}:pull"
TOKEN=$(curl -s "${REALM}?service=harbor-registry&scope=${SCOPE}" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token') or d.get('access_token') or '')")

echo "token 长度: ${#TOKEN}"
echo ""
echo "===== 1. 小层 blob 请求（带 -i 看响应头，-L 跟随重定向）====="
SMALL=$(curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
  "https://${REG}/v2/${REPO}/manifests/${TAG}" \
  | python3 -c "
import sys,json
m=json.load(sys.stdin)
ls=sorted(m['layers'], key=lambda x:x['size'])
print(ls[0]['digest'], ls[0]['size'])
")
DIG=$(echo $SMALL | awk '{print $1}'); SZ=$(echo $SMALL | awk '{print $2}')
echo "  测试层: $DIG  ($SZ bytes)"

echo ""
echo "  --- 不跟随重定向 (-i) ---"
curl -s -i --max-time 20 -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${DIG}" 2>&1 | head -15

echo ""
echo "===== 2. 跟随重定向下载小层，看真实速度 ====="
curl -sL -o /tmp/test-blob.bin -w "  HTTP %{http_code} | 下载 %{size_download} bytes | 速度 %{speed_download} B/s | 耗时 %{time_total}s\n" \
  --max-time 30 -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${DIG}" 2>&1

echo ""
echo "===== 3. 大层（198MB）跟随重定向，限时 15 秒看速度 ====="
BIG="sha256:73b36880f2edfa16fbc4a0030247398193e45d26ecce9a6cb396a8bc31787f4d"
curl -sL -o /dev/null -w "  HTTP %{http_code} | 下载 %{size_download} bytes | 速度 %{speed_download} B/s (%{speed_download} = %{speed_download})\n" \
  --max-time 15 -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${BIG}" 2>&1

python3 -c "
import subprocess
" 2>/dev/null
echo ""
echo "===== 4. 大层速度换算（重跑取 speed_download）====="
SPD=$(curl -sL -o /dev/null -w "%{speed_download}" --max-time 15 \
  -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${BIG}" 2>/dev/null)
python3 -c "
spd=float('${SPD}' or 0)
print(f'  {spd/1024:.0f} KiB/s  =  {spd/1024/1024:.2f} MB/s')
"

echo ""
echo "===== 5.  traceroute 看链路跳数（可选，超时跳过）====="
timeout 8 traceroute -m 8 -w 1 hub.bktencent.com 2>/dev/null | head -10 || echo "  traceroute 不可用"
