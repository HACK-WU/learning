#!/bin/bash
# 结课实战项目 · 临时文件清理
#
# 本轮亲手创建的临时文件清单（登记在案，只删清单内的）：
#   1. debug_min.py      — 最小复现脚本，定位卡点用，已无用        → 删
#   2. debug_stock.py    — 共用/独立连接对照实验                   → 保留（教学价值）
#   3. debug_stock2.py   — 原始返回值分布观察                      → 保留（教学价值）
#   4. debug_stock3.py   — 无歧义返回值验证                        → 保留（教学价值）
#   5. debug_scan.py     — SCAN 游标类型陷阱演示                   → 保留（教学价值）
#   6. __pycache__/      — Python 字节码缓存（可再生，已被 gitignore）→ 删
#
# 不删的：*.md / *.svg / 实现/ 下的 .py 源码（即使本轮亲手创建，也是最终产物）
set -u
IMPL=/mnt/d/projects/learning/redis/projects/电商大促数据层/实现

echo "===== 待删清单 ====="
echo "  1. $IMPL/debug_min.py   （一次性最小复现，已无用）"
echo "  2. $IMPL/__pycache__/   （字节码缓存，可再生）"
echo

cd "$IMPL"
rm -f debug_min.py && echo "  ✓ 已删 debug_min.py"
rm -rf __pycache__ && echo "  ✓ 已删 __pycache__/"

echo
echo "===== 保留（有教学价值，已登记）====="
for f in debug_stock.py debug_stock2.py debug_stock3.py debug_scan.py; do
  [ -f "$f" ] && echo "  ✓ 保留 $f"
done

echo
echo "===== 清理后的实现目录 ====="
ls -la "$IMPL" | grep -v '^total'
