#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
echo "===== 1. 全目录 md 链接终检 ====="
BAD=0; TOT=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  while IFS= read -r link; do
    TOT=$((TOT+1))
    [ -f "$dir/${link%%#*}" ] || { echo "  ❌ $(basename "$f") → $link"; BAD=$((BAD+1)); }
  done < <(grep -oE '\]\(([^)]+\.md)\)' "$f" | sed 's/](\(.*\))/\1/')
done < <(find "$R" -name '*.md')
echo "  共 $TOT 条，断链 $BAD 条"

echo
echo "===== 2. 运维专项 8 课齐备 ====="
ls "$R/子教程/运维专项/lessons/" | sed 's/^/  /'

echo
echo "===== 3. 索引同步 ====="
grep -o '进度：课 [0-9] / 8 已交付（[^）]*）' "$R/01-学习路径总览.md" | sed 's/^/  路径总览: /'
echo "  课程目录 课8 出现 $(grep -c '课 8 多机房与 K8s 运维视角' "$R/02-课程目录.md") 次"
grep -o '^- \[x\] 课 8：多机房与 K8s 运维视角' "$R/子教程/运维专项/overview.md" | sed 's/^/  overview: ✅ /'

echo
echo "===== 4. 环境清理 ====="
pkill -f 'consul agent' 2>/dev/null
sleep 2
echo "  consul 进程 = $(pgrep -fc 'consul agent' 2>/dev/null || echo 0)"
rm -rf /tmp/consul-ops/dualdc /tmp/consul-ops/tls/*.pem /tmp/consul-ops/tls/*.csr 2>/dev/null
echo "  双DC 测试数据已清理"
