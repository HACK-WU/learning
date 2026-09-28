#!/usr/bin/env bash
echo "=== 1. 安装根目录 ==="
ls -la /root/bk72/ 2>&1 | sed 's/^/  /'
echo ""
echo "=== 2. install 目录树（2层） ==="
find /root/bk72/install -maxdepth 2 -type d 2>/dev/null | sort | sed 's/^/  /'
echo ""
echo "=== 3. charts 目录（本地 tgz 包） ==="
ls -la /root/bk72/install/blueking/charts/ 2>&1 | head -25 | sed 's/^/  /'
echo ""
echo "=== 4. helm repo 列表（下载来源） ==="
helm repo list 2>&1 | sed 's/^/  /'
echo ""
echo "=== 5. environments/default 文件清单 ==="
ls -1 /root/bk72/install/blueking/environments/default/ 2>/dev/null | head -40 | sed 's/^/  /'
echo "  ... total: $(ls -1 /root/bk72/install/blueking/environments/default/ 2>/dev/null | wc -l)"
echo ""
echo "=== 6. env.yaml / defaults.yaml（全局配置） ==="
echo "  --- env.yaml ---"
sed 's/^/    /' /root/bk72/install/blueking/env.yaml 2>&1 | head -30
