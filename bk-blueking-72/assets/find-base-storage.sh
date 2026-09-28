#!/usr/bin/env bash
# 用途：定位 base-storage 批次的 helmfile，看清第一批到底包含哪些组件
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default

echo "===== 1. helmfile 主入口 ====="
ls -la "$E"/*.yaml* 2>/dev/null | head -20

echo ""
echo "===== 2. 找 seq 标记 / 批次划分 ====="
grep -rn "seq" "$E"/*.yaml* 2>/dev/null | head -20

echo ""
echo "===== 3. 找 base-storage 相关文件 ====="
find "$B" -iname '*base*storage*' 2>/dev/null | head -10
grep -rln "base-storage\|base_storage" "$B" 2>/dev/null | head -10

echo ""
echo "===== 4. 各 helmfile 里的 releases 数量 ====="
for f in "$E"/*.yaml "$E"/*.yaml.gotmpl; do
  [ -f "$f" ] || continue
  n=$(grep -cE '^\s*- name:' "$f" 2>/dev/null)
  [ "$n" -gt 0 ] && echo "$(basename "$f"): $n 个 release"
done
