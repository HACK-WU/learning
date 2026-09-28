#!/usr/bin/env bash
# 并发测速：区分「单连接限速」vs「总带宽上限」
# 关键修正：必须 -L 跟随 307 重定向到 COS
set -uo pipefail
REG=hub.bktencent.com
REPO=bitnami/elasticsearch
TAG=7.16.2-debian-10-r0
WORK=/tmp/registry-concurrent
rm -rf "$WORK"; mkdir -p "$WORK"

TOKEN=$(curl -s "https://${REG}/service/token?service=harbor-registry&scope=repository:${REPO}:pull" \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token') or d.get('access_token') or '')")

curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
  "https://${REG}/v2/${REPO}/manifests/${TAG}" \
  | python3 -c "
import sys,json
m=json.load(sys.stdin)
for l in sorted(m['layers'],key=lambda x:-x['size'])[:8]:
    print(l['digest'])
" > "$WORK/digests.txt"

mapfile -t DIGS < "$WORK/digests.txt"
echo "待测大层数量: ${#DIGS[@]}"
echo ""

run_one() {
  local idx=$1 dig=$2 dur=$3
  curl -sL -o /dev/null -w "%{speed_download}" --max-time "$dur" \
    -H "Authorization: Bearer $TOKEN" \
    "https://${REG}/v2/${REPO}/blobs/${dig}" > "$WORK/r$idx.txt" 2>/dev/null
}

echo "===== A. 单连接基准（10秒）====="
run_one 0 "${DIGS[0]}" 10
python3 -c "
v=float(open('$WORK/r0.txt').read().strip() or 0)
print(f'  {v/1024:.0f} KiB/s  ({v/1024/1024:.2f} MB/s)')
"

echo ""
echo "===== B. 4 并发（10秒）====="
for i in 1 2 3 4; do run_one "c$i" "${DIGS[$i]}" 10 & done
wait
python3 -c "
import glob
tot=0;n=0
for f in sorted(glob.glob('$WORK/rc*.txt')):
    v=float(open(f).read().strip() or 0); tot+=v; n+=1
    print(f'  连接{n}: {v/1024:.0f} KiB/s')
print(f'  合计: {tot/1024:.0f} KiB/s ({tot/1024/1024:.2f} MB/s)')
"

echo ""
echo "===== C. 8 并发（10秒）====="
for i in 0 1 2 3 4 5 6 7; do run_one "d$i" "${DIGS[$i]}" 10 & done
wait
python3 -c "
import glob
tot=0;n=0
for f in sorted(glob.glob('$WORK/rd*.txt')):
    v=float(open(f).read().strip() or 0); tot+=v; n+=1
print(f'  {n} 连接合计: {tot/1024:.0f} KiB/s ({tot/1024/1024:.2f} MB/s)')
"

echo ""
echo "===== D. 对比：直连 COS 域名（绕过 registry 重定向）====="
# 取一个重定向后的 Location，测 COS 裸速
LOC=$(curl -s -o /dev/null -w "%{redirect_url}" --max-time 10 \
  -H "Authorization: Bearer $TOKEN" \
  "https://${REG}/v2/${REPO}/blobs/${DIGS[0]}")
echo "  COS 域名: $(echo "$LOC" | sed -n 's|https://\([^/]*\)/.*|\1|p')"
curl -sL -o /dev/null -w "  COS 直连速度: %{speed_download} B/s\n" --max-time 10 "$LOC" 2>/dev/null
python3 -c "
import subprocess
" 2>/dev/null

echo ""
echo "===== E. 对照组：测一个非腾讯源（判断是本机出口还是对端）====="
curl -sL -o /dev/null -w "  公网对照(dockerhub): %{speed_download} B/s\n" --max-time 10 \
  "https://registry-1.docker.io/v2/" 2>/dev/null || echo "  dockerhub 不可达"
