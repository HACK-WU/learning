#!/bin/bash
# 结课实战项目 · 卫生检查：忽略规则 + 临时文件清理
set -u
REPO=/mnt/d/projects/learning/redis

echo "===== 1. 仓库根是否已有 .gitignore ====="
if [ -f "$REPO/.gitignore" ]; then
  echo "  已存在，内容："
  sed 's/^/    /' "$REPO/.gitignore"
else
  echo "  不存在 → 需创建基线"
fi

echo
echo "===== 2. 本轮新增的过程残留 ====="
ls -d "$REPO/projects/电商大促数据层/实现/__pycache__" 2>/dev/null && echo "  ↑ Python 字节码缓存（过程残留）"

echo
echo "===== 3. 检查是否误伤教学产物 ====="
echo "  *.md 文件数：$(find "$REPO" -name '*.md' | wc -l)"
echo "  *.svg 文件数：$(find "$REPO" -name '*.svg' | wc -l)"
echo "  实现/ 下 .py 文件数：$(find "$REPO/projects" -name '*.py' | wc -l)"
