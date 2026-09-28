#!/usr/bin/env bash
# 用途：装官方 yq/jq，然后生成 app_secret（24个 app_code 的 uuid）
set -uo pipefail
BIN=/root/bk72/tools/bin
B=/root/bk72/install/blueking
E=$B/environments/default
CACHE=/root/.cache/bkdl/ce7/tools

echo "===== 1. 从缓存解压 yq / jq 到 tools/bin ====="
mkdir -p "$BIN"
for n in yq jq; do
  f=$(ls "$CACHE"/$n-*.xz 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    cp "$f" /tmp/ 2>/dev/null
    xz -dk -c "$f" > "$BIN/$n" 2>/dev/null && chmod +x "$BIN/$n"
    echo "$n -> $($BIN/$n --version 2>&1 | head -1)"
  else
    echo "$n 缓存未找到"
  fi
done

echo ""
echo "===== 2. 链到 PATH ====="
ln -sf "$BIN/yq" /usr/local/bin/yq 2>/dev/null
ln -sf "$BIN/jq" /usr/local/bin/jq 2>/dev/null
export PATH="$BIN:$PATH"
echo "yq: $(command -v yq) $(yq --version 2>&1 | head -1)"
echo "jq: $(command -v jq) $(jq --version 2>&1 | head -1)"

echo ""
echo "===== 3. 生成 app_secret（24个 app_code，用 uuidgen/python 替代 uuid 命令）====="
APP_CODES=(bk_repo bk_paas bk_iam bk_ssm bk_apigateway bk_apigw_test bk_cmdb bk_job bk_gse bk_paas3 bk_usermgr bk_ci bk_monitorv3 bk_bkdata bk_log_search bk_bcs_app bk_codecc bk_nodeman bk_dbm bk_notice bk_bscp bk_flow_engine bk_audit)
gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen
  else python3 -c "import uuid;print(uuid.uuid4())"; fi
}
{
  echo "# app_code对应的app_secret值"
  echo "appSecret:"
  for c in "${APP_CODES[@]}"; do
    printf "  %s: %s\n" "$c" "$(gen_uuid | tr 'A-Z' 'a-z')"
  done
} > "$E/app_secret.yaml"

echo "已生成 $E/app_secret.yaml"
head -6 "$E/app_secret.yaml"
echo "..."
echo "条目数: $(grep -cE '^  [a-z_]+:' "$E/app_secret.yaml")"
