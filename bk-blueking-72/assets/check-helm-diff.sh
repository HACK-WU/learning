#!/usr/bin/env bash
# 核查 helm-diff 插件状态，并准备安装
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH

echo "===== 1. helm plugin list ====="
helm plugin list 2>&1

echo ""
echo "===== 2. 离线包是否存在 ====="
ls -la /root/bk72/tools/bin/helm-plugin-diff.tgz 2>&1
echo "  内容预览:"
tar -tzf /root/bk72/tools/bin/helm-plugin-diff.tgz 2>/dev/null | head -8

echo ""
echo "===== 3. helm 插件目录 ====="
ls -la /root/.local/share/helm/plugins/ 2>/dev/null || echo "  插件目录不存在"
ls -la /root/.cache/helm/plugins/ 2>/dev/null | head -5

echo ""
echo "===== 4. 是否已有 diff 插件残留 ====="
find /root -maxdepth 6 -name 'plugin.yaml' -path '*diff*' 2>/dev/null | head -5

echo ""
echo "===== 5. helm 环境变量 ====="
helm env 2>&1 | grep -iE 'PLUGIN|HELM_' | head -8
