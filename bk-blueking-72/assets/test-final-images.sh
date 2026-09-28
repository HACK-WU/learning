#!/usr/bin/env bash
# 用途：修正解析（按 tab 分列取第3列），全量 40 个 chart 的镜像可达性判定
set -uo pipefail
F=/root/bk72/chart-images/blueking/chart-images.txt
R=hub.bktencent.com
OUT=/root/bk72/render_test/image_final.txt
: > "$OUT"

get_token() {
  curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$1:pull" \
    | grep -oE '"token":"[^"]+"' | sed 's/"token":"//; s/"$//' | head -1
}

probe() { # repo tag -> httpcode
  local t=$(get_token "$1")
  curl -s -o /dev/null -w "%{http_code}" --max-time 25 \
    -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
    "https://$R/v2/$1/manifests/$2"
}

# 逐行：第1列 chart，第2列版本，第3列起是镜像列表（空格分隔，可能带 @sha256）
while IFS=$'\t' read -r chart ver imgs; do
  [ -z "${imgs:-}" ] && continue
  first=$(echo "$imgs" | awk '{print $1}')
  # 解析 repo/tag：去 registry 前缀、处理 @sha256
  f="${first#*://}"; f="${f#*/}"
  repo="${f%@*}"; repo="${repo%:*}"
  ref="${f##*@}"; [ "$ref" = "$f" ] && ref="${f##*:}"
  [ -z "$repo" ] && continue
  code=$(probe "$repo" "$ref")
  printf "%s\t%s\t%s:%s\n" "$code" "$chart" "$repo" "$ref" >> "$OUT"
done < "$F"

echo "===== 全量镜像可达性（每 chart 首镜像）====="
echo "总探测: $(wc -l < "$OUT")"
echo ""
echo "--- 结果分布 ---"
cut -f1 "$OUT" | sort | uniq -c | sort -rn

echo ""
echo "--- 200 可拉（前15）---"
grep '^200' "$OUT" | cut -f2,3 | head -15

echo ""
echo "--- 非 200（需关注）---"
grep -v '^200' "$OUT" | cut -f1,2,3 | head -15

echo ""
echo "===== ★ 判定 ====="
ok=$(grep -c '^200' "$OUT" || true)
tot=$(wc -l < "$OUT")
echo "可拉: $ok / $tot"
