#!/usr/bin/env bash
# 诊断：hub.bktencent.com 拉取慢的瓶颈定位
# 三层验证：链路延迟 / 单连接限速 / 总带宽上限
set -uo pipefail
REG=hub.bktencent.com
REPO=bitnami/elasticsearch
TAG=7.16.2-debian-10-r0
WORK=/tmp/registry-speedtest
rm -rf "$WORK"; mkdir -p "$WORK"

echo "===== 0. WSL 代理设置 ====="
env | grep -iE 'proxy' || echo "  无代理环境变量"

echo ""
echo "===== 1. 认证探测 ====="
HDRS=$(curl -sI "https://${REG}/v2/${REPO}/manifests/${TAG}")
echo "$HDRS" | grep -iE 'HTTP/|www-authenticate' || echo "  无认证头"
REALM=$(echo "$HDRS" | grep -i www-authenticate | sed -n 's/.*realm="\([^"]*\)".*/\1/p')
SERVICE=$(echo "$HDRS" | grep -i www-authenticate | sed -n 's/.*service="\([^"]*\)".*/\1/p')
SCOPE=$(echo "$HDRS" | grep -i www-authenticate | sed -n 's/.*scope="\([^"]*\)".*/\1/p')
echo "  realm=$REALM  service=$SERVICE"
TOKEN=$(curl -s "${REALM}?service=${SERVICE}&scope=${SCOPE}" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token') or d.get('access_token') or '')" 2>/dev/null)
echo "  token 长度: ${#TOKEN}"

echo ""
echo "===== 2. manifest 与 layer 大小 (Top6) ====="
curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
  "https://${REG}/v2/${REPO}/manifests/${TAG}" -o "$WORK/manifest.json"
python3 - "$WORK/manifest.json" <<'PY' > "$WORK/layers.txt"
import json,sys
m=json.load(open(sys.argv[1]))
for l in m.get('layers',[]):
    print(f"{l['size']}\t{l['digest']}")
PY
echo "  layer 数: $(wc -l < "$WORK/layers.txt")"
sort -rn "$WORK/layers.txt" | head -6 | awk '{printf "  %6.1f MB  %s\n", $1/1024/1024, $2}'
TOP=$(sort -rn "$WORK/layers.txt" | head -1 | awk '{print $2}')

echo ""
echo "===== 3. 链路延迟（DNS/TCP/TLS/首字节）====="
curl -s -o /dev/null \
  -w "  DNS %{time_namelookup}s | TCP %{time_connect}s | TLS %{time_appconnect}s | 首字节 %{time_starttransfer}s\n" \
  --max-time 15 -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${TOP}"

echo ""
echo "===== 4. 单连接测速（8秒，最大层）====="
curl -s -o /dev/null -w "%{speed_download}" --max-time 8 \
  -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${TOP}" > "$WORK/single.txt" 2>/dev/null

echo ""
echo "===== 5. 四并发测速（8秒）====="
i=0
for d in $(sort -rn "$WORK/layers.txt" | head -4 | awk '{print $2}'); do
  i=$((i+1))
  ( curl -s -o /dev/null -w "%{speed_download}" --max-time 8 \
      -H "Authorization: Bearer $TOKEN" \
      "https://${REG}/v2/${REPO}/blobs/${d}" > "$WORK/c$i.txt" 2>/dev/null ) &
done
wait

echo ""
echo "===== 结果汇总 ====="
python3 - "$WORK" <<'PY'
import glob,os,sys
w=sys.argv[1]
def rd(p):
    try: return float(open(p).read().strip() or 0)
    except: return 0.0
single=rd(os.path.join(w,'single.txt'))
tot=0.0;n=0
for f in sorted(glob.glob(os.path.join(w,'c*.txt'))):
    v=rd(f); tot+=v; n+=1
    print(f"  连接{n}: {v/1024/1024:.2f} MB/s")
print(f"  ----------------------------------")
print(f"  单连接基准: {single/1024/1024:.2f} MB/s  ({single/1024:.0f} KiB/s)")
print(f"  四并发合计: {tot/1024/1024:.2f} MB/s")
print(f"  并发提升  : {(tot/single if single else 0):.2f}x")
PY
