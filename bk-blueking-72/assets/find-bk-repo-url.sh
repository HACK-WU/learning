#!/usr/bin/env bash
set -uo pipefail
echo "===== 1. 配置里找 blueking repo 地址 ====="
grep -rnE 'blueking.*https?://|repo.*bktencent|charts\.bktencent' /root/bk72/install/blueking/ 2>/dev/null | grep -v Binary | head -10

echo ""
echo "===== 2. defaults.yaml / env.yaml 里的仓库定义 ====="
grep -nE 'repo|repository|url' /root/bk72/install/blueking/defaults.yaml 2>/dev/null | head -15
echo "--- env.yaml ---"
cat /root/bk72/install/blueking/env.yaml 2>/dev/null | head -25

echo ""
echo "===== 3. bkdl 脚本头部（看下载逻辑）====="
head -40 /root/bk72/bin/bkdl-7.2-stable.sh 2>/dev/null

echo ""
echo "===== 4. 版本清单（看需要哪些 chart）====="
cat /root/bk72/install/blueking/environments/default/version.yaml 2>/dev/null | head -40
