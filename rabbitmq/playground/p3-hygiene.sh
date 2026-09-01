#!/usr/bin/env bash
# Phase 3 卫生检查：本轮新增文件分类 + .gitignore 校验
cd /mnt/d/projects/learning/rabbitmq || exit 1

echo "=== 顶层目录 ==="
ls -d */
echo

echo "=== 本轮新增（未跟踪，聚合模式）==="
git status --porcelain | grep '^??' | head -20
echo

echo "=== 修改的 md/py（rabbitmq 主题相关）==="
git status --porcelain | grep -E '^ M' | grep -vE 'animation-engine|other-topic' | head -20
echo

echo "=== __pycache__ 目录 ==="
find . -name '__pycache__' -type d 2>/dev/null | head -10
echo

echo "=== check-ignore 校验 ==="
paths=(
  "projects/订单履约消息系统/实现/__pycache__"
  "projects/订单履约消息系统/实现/config.py"
  "projects/订单履约消息系统/实现/verify.py"
  "projects/订单履约消息系统/README.md"
  "projects/订单履约消息系统/设计决策.md"
  "projects/订单履约消息系统/反例对照.md"
  "projects/订单履约消息系统/验收清单.md"
)
for p in "${paths[@]}"; do
  if git check-ignore -q "$p"; then
    echo "  [忽略] $p"
  else
    echo "  [提交] $p"
  fi
done
echo

echo "=== pycache 下的文件数 ==="
find projects -name '*.pyc' 2>/dev/null | wc -l
