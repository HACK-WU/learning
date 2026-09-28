#!/usr/bin/env bash
echo "=== 1. index.yaml 中 bk-cmdb 段原始文本 ==="
awk '/^  bk-cmdb:/,/^  bk-[a-z]+:/' /tmp/idx.yaml 2>/dev/null | head -20

echo ""
echo "=== 2. 直接搜 tgz 链接 ==="
grep -oE 'https?://[^ ]*bk-cmdb[^ ]*\.tgz' /tmp/idx.yaml 2>/dev/null | head -3
grep -oE '(chartrepo|charts)/[^ ]*bk-cmdb[^ ]*\.tgz' /tmp/idx.yaml 2>/dev/null | head -3

echo ""
echo "=== 3. 检查 idx.yaml 是否下载完整 ==="
ls -la /tmp/idx.yaml 2>/dev/null
head -3 /tmp/idx.yaml 2>/dev/null
