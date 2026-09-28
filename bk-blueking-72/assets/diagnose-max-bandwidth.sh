#!/usr/bin/env bash
# 探测总带宽上限：16 / 24 并发
# 目的：确认「多镜像并行拉取」是否有加速空间
set -uo pipefail
REG=hub.bktencent.com
WORK=/tmp/registry-maxbw
rm -rf "$WORK"; mkdir -p "$WORK"

# 用 3 个不同镜像凑够 24 个互不相同的 blob，模拟真实多镜像并行
declare -A TOK
for R in bitnami/elasticsearch bitnami/etcd bitnami/zookeeper; do
  TOK[$R]=$(curl -s "https://${REG}/service/token?service=harbor-registry&scope=repository:${R}:pull" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token') or d.get('access_token') or '')")
done

# 收集候选 blob（镜像:digest）
: > "$WORK/all.txt"
for R in bitnami/elasticsearch bitnami/etcd bitnami/zookeeper; do
  T=${TOK[$R]}
  for TAG in 7.16.2-debian-10-r0 3.5.4-debian-11-r31 3.8.0-debian-10-r20; do
    curl -s -H "Authorization: Bearer $T" \
      -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
      "https://${REG}/v2/${R}/manifests/${TAG}" 2>/dev/null \
      | python3 -c "
import sys,json
try:
    m=json.load(sys.stdin)
    for l in sorted(m.get('layers',[]),key=lambda x:-x['size'])[:4]:
        print('$R',l['digest'])
except: pass
" >> "$WORK/all.txt"
  done
done
sort -u "$WORK/all.txt" > "$WORK/uniq.txt"
echo "可用唯一 blob 数: $(wc -l < "$WORK/uniq.txt")"

pull_one() {
  local idx=$1 repo=$2 dig=$3 dur=$4
  local t=${TOK[$repo]}
  curl -sL -o /dev/null -w "%{speed_download}" --max-time "$dur" \
    -H "Authorization: Bearer $t" \
    "https://${REG}/v2/${repo}/blobs/${dig}" > "$WORK/p$idx.txt" 2>/dev/null
}

for N in 16 24; do
  rm -f "$WORK"/p*.txt
  i=0
  while IFS=' ' read -r repo dig; do
    [ $i -ge $N ] && break
    pull_one $i "$repo" "$dig" 12 &
    i=$((i+1))
  done < "$WORK/uniq.txt"
  wait
  python3 -c "
import glob
fs=sorted(glob.glob('$WORK/p*.txt'))
vals=[float(open(f).read().strip() or 0) for f in fs]
tot=sum(vals)
print(f'  {len(vals):2d} 并发合计: {tot/1024:6.0f} KiB/s  ({tot/1024/1024:.2f} MB/s)   最小 {min(vals)/1024:.0f} / 最大 {max(vals)/1024:.0f} KiB/s')
"
done

echo ""
echo "===== 结论参考 ====="
echo "  单连接 ~120 KiB/s（COS 侧单连接限速）"
echo "  线性区说明：总带宽远未饱和，多镜像并行有加速空间"
