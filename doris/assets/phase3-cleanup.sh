#!/usr/bin/env bash
# Phase 3 探测脚本清理
# 保留：phase3-task1~5 交付脚本 + phase3-linkcheck.sh
# 删除：phase3-probe1 ~ phase3-probe33（内部探测用，不属于交付物）
set -u
cd /mnt/d/projects/learning/doris/assets

echo "=== 清理前 phase3-* 脚本 ==="
ls phase3-*.sh | wc -l
echo

echo "=== 删除 probe 脚本 ==="
rm -f phase3-probe*.sh
echo "  已删除 phase3-probe*.sh"
echo

echo "=== 清理后 phase3-* 脚本 ==="
ls -1 phase3-*.sh
echo
echo "  共 $(ls phase3-*.sh | wc -l) 个"
echo
echo "=== done ==="
