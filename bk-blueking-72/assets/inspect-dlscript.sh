#!/usr/bin/env bash
# 用途：只读探索 bkdl-7.2-stable.sh 用法与下载规模，不执行实际下载
set -uo pipefail

S=/root/bk72/bin/bkdl-7.2-stable.sh

echo "===== 1. 用法帮助 ====="
bash "$S" --help 2>&1 | head -40

echo ""
echo "===== 2. 通道与版本相关变量 ====="
grep -nE 'release_channel|release_version|release_baseurl' "$S" | head -15

echo ""
echo "===== 3. 会下载哪些制品（清单文件名）====="
grep -oE '[a-z0-9_.-]*\.(txt|list|json|yaml|sha256|md5)' "$S" | sort -u | head -15

echo ""
echo "===== 4. 主要功能函数 ====="
grep -nE '^[a-z_]+\s*\(\)' "$S" | head -25
