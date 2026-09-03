#!/usr/bin/env bash
set -euo pipefail

echo "=== [1] 检测是否已安装 ==="
if command -v surreal >/dev/null 2>&1; then
  echo "已安装: $(surreal version 2>&1 | head -5)"
else
  echo "未安装，准备安装..."
fi

echo ""
echo "=== [2] 系统信息 ==="
uname -a
echo "arch: $(uname -m)"

echo ""
echo "=== [3] 安装 SurrealDB（官方安装脚本）==="
curl --proto '=https' --tlsv1.2 -sSf https://install.surrealdb.com | sh

echo ""
echo "=== [4] 验证安装 ==="
export PATH="$HOME/.surrealdb:/usr/local/bin:$PATH"
command -v surreal || echo "PATH 中找不到 surreal，尝试常见路径"
ls -la "$HOME/.surrealdb" 2>/dev/null || true
ls -la /usr/local/bin/surreal 2>/dev/null || true

echo ""
echo "=== [5] 版本 ==="
surreal version 2>&1 | head -20 || true

echo ""
echo "=== INSTALL_DONE ==="
