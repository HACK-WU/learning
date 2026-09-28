#!/usr/bin/env bash
# 用途：全量镜像可达性实测——用匿名 token 验证多个真实镜像
set -uo pipefail
R=hub.bktencent.com
OUT=/root/bk72/render_test/image_result.txt

get_token() {
  curl -s --max-time 20 "https://$R/service/token?service=harbor-registry&scope=repository:$1:pull" \
    | grep -oE '"token":"[^"]+"' | sed 's/"token":"//; s/"$//' | head -1
}

check() {  # repo tag
  local repo="$1" tag="$2"
  local t=$(get_token "$repo")
  [ -z "$t" ] && { echo "NOTOKEN $repo:$tag"; return; }
  local code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 25 \
    -H "Authorization: Bearer $t" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.manifest.v1+json" \
    "https://$R/v2/$repo/manifests/$tag")
  echo "$code $repo:$tag"
}

: > "$OUT"
echo "===== 基础存储类镜像（渲染已确认的真实名）====="
check bitnami/mysql 8.0.37-debian-12-r2 | tee -a "$OUT"
check bitnami/redis 6.2.7-debian-11-r11 | tee -a "$OUT"
check bitnami/mongodb 4.4.10-debian-10-r44 | tee -a "$OUT"

echo ""
echo "===== 蓝鲸自研组件镜像（按官方命名规则推测，标注为推测）====="
for r in blueking/cmdb-apiserver blueking/bk-job blueking/bk-iam blueking/bk-paas3 blueking/gse-server blueking/bk-user blueking/apigateway blueking/bk-monitor blueking/bk-log-search blueking/bk-repo; do
  check "$r" latest | tee -a "$OUT"
done

echo ""
echo "===== 汇总 ====="
echo "200 数量: $(grep -c '^200' "$OUT")"
echo "404 数量: $(grep -c '^404' "$OUT")"
echo "401/403 数量: $(grep -cE '^40[13]' "$OUT")"
