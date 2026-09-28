#!/usr/bin/env bash
# 用途：修正 repo 前缀剥离 bug，重统计自研镜像可拉率（决定性）
set -uo pipefail
R=hub.bktencent.com
F=/root/bk72/chart-images/blueking/chart-images.txt
OUT=/root/bk72/render_test/self_images2.txt
: > "$OUT"

strip() {  # 去掉 registry 前缀，只留 repo
  local s="$1"
  s="${s#*://}"
  case "$s" in
    "$R"/*) s="${s#$R/}" ;;
    */blueking/*|*/bitnami/*|*/library/*|*/groundnuty/*|*/ingress-nginx/*|*/sig-storage/*) s="${s#*/}" ;;
  esac
  printf '%s' "$s"
}

tot=0; ok=0
while IFS=$'\t' read -r chart ver imgs; do
  [ -z "${imgs:-}" ] && continue
  for im in $imgs; do
    im="${im%$'\r'}"
    case "$im" in *blueking/*) ;; *) continue ;; esac
    full=$(strip "$im")
    r2="${full%@*}"; r2="${r2%:*}"; rf="${full##*@}"; [ "$rf" = "$full" ] && rf="${full##*:}"
    [ -z "$r2" ] && continue
    tot=$((tot+1))
    T=$(curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$r2:pull" | grep -oE '"token":"[^"]+"' | sed 's/"token":"//;s/"$//' | head -1)
    c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 -H "Authorization: Bearer $T" \
       -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json" \
       "https://$R/v2/$r2/manifests/$rf")
    printf "%s\t%s:%s\n" "$c" "$r2" "$rf" >> "$OUT"
    [ "$c" = "200" ] && ok=$((ok+1))
  done
done < "$F"

echo "===== 自研 blueking 镜像可拉率（修正后）====="
echo "可拉: $ok / $tot"
echo ""
echo "--- 分布 ---"
cut -f1 "$OUT" | sort | uniq -c | sort -rn
echo ""
echo "--- 非200 清单 ---"
grep -v '^200' "$OUT" | cut -f1,2 | head -20
