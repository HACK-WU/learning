#!/usr/bin/env bash
# 用途：深挖 14 个非200 的真实原因——判定是真障碍还是脚本/命名问题
set -uo pipefail
F=/root/bk72/chart-images/blueking/chart-images.txt
R=hub.bktencent.com

get_token() {
  curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$1:pull" \
    | grep -oE '"token":"[^"]+"' | sed 's/"token":"//; s/"$//' | head -1
}
probe() {
  local t=$(get_token "$1")
  curl -s -o /dev/null -w "%{http_code}" --max-time 25 \
    -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
    "https://$R/v2/$1/manifests/$2"
}

echo "===== 1. 所有非200 chart 的「全部」镜像逐个探测（不只第一个）====="
while IFS=$'\t' read -r chart ver imgs; do
  [ -z "${imgs:-}" ] && continue
  # 先探第一个，非200才展开
  first=$(echo "$imgs" | awk '{print $1}')
  f="${first#*://}"; f="${f#*/}"
  repo="${f%@*}"; repo="${repo%:*}"; ref="${f##*@}"; [ "$ref" = "$f" ] && ref="${f##*:}"
  c=$(probe "$repo" "$ref")
  if [ "$c" != "200" ]; then
    echo "### $chart (首镜像 $c) —— 展开全部镜像:"
    for im in $imgs; do
      g="${im#*://}"; g="${g#*/}"
      r2="${g%@*}"; r2="${r2%:*}"; rf="${g##*@}"; [ "$rf" = "$g" ] && rf="${g##*:}"
      c2=$(probe "$r2" "$rf")
      echo "   $c2  $r2:$rf"
    done
  fi
done < "$F"

echo ""
echo "===== 2. influxdb 400 的具体错误（可能是 tag 格式问题）====="
t=$(get_token "influxdb")
curl -s --max-time 20 -H "Authorization: Bearer $t" \
  -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://$R/v2/influxdb/manifests/1.8.6-alpine" | head -c 300
