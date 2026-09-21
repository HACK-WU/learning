#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
echo "===== stages 目录 ====="
ls "$R/stages/" | sed 's/^/  /'
echo
echo "===== 含关键词的文件 ====="
for kw in 多数据中心 服务网格 退出 迁移 决策; do
  echo "  --- $kw ---"
  find "$R/stages" -name "*${kw}*" -type f 2>/dev/null | sed "s|$R/||" | sed 's/^/    /'
done
