#!/usr/bin/env bash
set -uo pipefail
F=/root/bk72/install/blueking/base-blueking.yaml.gotmpl
echo "===== 确认 base-blueking 中 seq=first 的 release 与 chart 来源 ====="
grep -nE '^\s+- name:|^\s+chart:|^\s+seq:' "$F" 2>/dev/null | head -24

echo ""
echo "===== base-storage 对比（本地 tgz）====="
grep -nE 'chart:' /root/bk72/install/blueking/base-storage.yaml.gotmpl 2>/dev/null | head -4

echo ""
echo "===== 结论用：base.yaml.gotmpl 的 helmfiles 结构 ====="
cat /root/bk72/install/blueking/base.yaml.gotmpl
