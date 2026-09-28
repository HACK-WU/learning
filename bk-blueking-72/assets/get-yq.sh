#!/usr/bin/env bash
# 用途：从官方 tools 获取 yq（避免装系统包），再生成 app_secret
set -uo pipefail
S=/root/bk72/bin/bkdl-7.2-stable.sh
BIN=/root/bk72/tools
B=/root/bk72/install/blueking
E=$B/environments/default

echo "===== 1. 下载官方 yq ====="
timeout 300 bash "$S" -r 7.2.19 -i "$BIN" yq 2>&1 | grep -vE '^\s*[#%]|%$' | tail -5

echo ""
echo "===== 2. 定位 yq 可执行文件 ====="
YQ=$(find "$BIN" /root/bk72 -name 'yq*' -type f 2>/dev/null | grep -vE '\.tgz|\.xz|\.gz' | head -3)
echo "候选: $YQ"
YF=$(echo "$YQ" | head -1)
if [ -n "$YF" ]; then
  chmod +x "$YF"
  echo "版本: $($YF --version 2>&1 | head -1)"
  # 软链到 PATH
  ln -sf "$YF" /usr/local/bin/yq 2>/dev/null && echo "已链到 /usr/local/bin/yq"
fi

echo ""
echo "===== 3. 验证 yq 可用 ====="
command -v yq >/dev/null 2>&1 && yq --version 2>&1 | head -1 || echo "yq 仍不可用"

echo ""
echo "===== 4. 重新生成 app_secret ====="
cd "$E" || exit 1
timeout 120 bash "$B/scripts/generate_app_secret.sh" 2>&1 | tail -8

echo ""
echo "===== 5. 检查生成结果 ====="
[ -f "$E/app_secret.yaml" ] && { echo "★ 已生成"; head -10 "$E/app_secret.yaml"; } || echo "✗ 未生成"
