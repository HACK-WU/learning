#!/usr/bin/env bash
# 用途：用官方总表里的「真实镜像名」做可达性实测
set -uo pipefail
F=/root/bk72/chart-images/blueking/chart-images.txt
R=hub.bktencent.com
OUT=/root/bk72/render_test/image_real.txt

echo "===== 0. 总表概况 ====="
echo "总行数: $(wc -l < "$F")"
echo "样例:"; head -5 "$F"

get_token() {
  curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$1:pull" \
    | grep -oE '"token":"[^"]+"' | sed 's/"token":"//; s/"$//' | head -1
}

: > "$OUT"
echo ""
echo "===== 1. 随机抽样 15 个真实镜像实测 ====="
mapfile -t SAMPLES < <(shuf -n 15 "$F" 2>/dev/null | tr -d '\r')
for line in "${SAMPLES[@]}"; do
  full="${line##* }"                 # 取镜像全名（可能带仓库前缀）
  full="${full#hub.bktencent.com/}"  # 去掉 registry 前缀
  repo="${full%%:*}"; tag="${full##*:}"
  [ -z "$repo" ] || [ "$repo" = "$full" ] && continue
  t=$(get_token "$repo")
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 \
    -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
    "https://$R/v2/$repo/manifests/$tag")
  printf "%s  %s:%s\n" "$code" "$repo" "$tag" | tee -a "$OUT"
done

echo ""
echo "===== 2. 汇总 ====="
echo "200(可拉): $(grep -c '^200' "$OUT") / $(wc -l < "$OUT")"
echo "404: $(grep -c '^404' "$OUT")"
echo "401/403: $(grep -cE '^40[13]' "$OUT")"
