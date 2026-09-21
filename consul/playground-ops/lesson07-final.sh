#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
echo "===== 1. 全目录 md 链接校验（以各文件所在目录为基准）====="
BAD=0; TOT=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  while IFS= read -r link; do
    TOT=$((TOT+1))
    tgt="$dir/${link%%#*}"
    [ -f "$tgt" ] || { echo "  ❌ $(basename $f) → $link"; BAD=$((BAD+1)); }
  done < <(grep -oE '\]\(([^)]+\.md)\)' "$f" | sed 's/](\(.*\))/\1/')
done < <(find "$R" -name '*.md')
echo "  共 $TOT 条，断链 $BAD 条"

echo
echo "===== 2. 课7 文件与结构 ====="
L7="$R/子教程/运维专项/lessons/lesson-07-版本升级与迁移.md"
echo "  大小: $(wc -c < "$L7") 字节, 行数: $(wc -l < "$L7")"
echo "  实测边界标注: $(grep -c '实测边界' "$L7")"
echo "  官方引用: $(grep -c 'docs.hashicorp.com\|consul.io/docs' "$L7")"

echo
echo "===== 3. 索引同步确认 ====="
grep -o '进度：课 [0-9] / 8 已交付（[^）]*）' "$R/01-学习路径总览.md" | sed 's/^/  路径总览: /'
grep -c '课 7 版本升级与迁移' "$R/02-课程目录.md" | xargs -I{} echo "  课程目录: 课7 出现 {} 次"
grep -o '^- \[x\] 课 7：版本升级与迁移' "$R/子教程/运维专项/overview.md" | sed 's/^/  overview: ✅ /'

echo
echo "===== 4. 环境清理 ====="
pkill -f 'consul agent' 2>/dev/null
sleep 2
echo "  剩余 consul 进程 = $(pgrep -fc 'consul agent' 2>/dev/null || echo 0)"
rm -f /tmp/consul-ops/tls/*.pem /tmp/consul-ops/tls/*.csr /tmp/consul-ops/tls/*.srl 2>/dev/null
echo "  临时证书已清理"
