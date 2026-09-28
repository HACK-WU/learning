#!/usr/bin/env bash
# 安装 helm-diff 插件（离线包，无需联网）
# 包内路径：.local/share/helm/plugins/helm-diff/
# 解压到 /root/ 即可归位
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. 安装前 ====="
helm plugin list 2>&1

echo ""
echo "===== 2. 解压离线包到 /root/ ====="
tar -xzf /root/bk72/tools/bin/helm-plugin-diff.tgz -C /root/ 2>&1
echo "  退出码: $?"

echo ""
echo "===== 3. 验证插件目录 ====="
ls -la /root/.local/share/helm/plugins/helm-diff/ 2>&1 | head -8

echo ""
echo "===== 4. 找可执行二进制 ====="
find /root/.local/share/helm/plugins/helm-diff -maxdepth 2 -type f \( -name 'diff' -o -name 'helm-diff' \) 2>/dev/null
cat /root/.local/share/helm/plugins/helm-diff/plugin.yaml 2>/dev/null

echo ""
echo "===== 5. helm plugin list（验证是否识别）====="
helm plugin list 2>&1
