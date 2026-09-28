#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. /root/bk72/bin 内容 ====="
ls -la /root/bk72/bin/ 2>&1 | head -20

echo ""
echo "===== 2. 之前 base-storage 是怎么部署的（历史命令）====="
grep -iE 'helmfile' /root/.bash_history 2>/dev/null | tail -15

echo ""
echo "===== 3. 找 helmfile 二进制 ====="
find /root/bk72 /usr/local /opt -maxdepth 3 -name 'helmfile*' 2>/dev/null | head -10

echo ""
echo "===== 4. 渲染测试目录（可能有现成渲染产物）====="
ls -la /root/bk72/render_test/ 2>/dev/null | head -10
