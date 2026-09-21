#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
B="$R/子教程/运维专项/lessons"
L8="$B/lesson-08-多机房与K8s运维视角.md"

echo "===== 1. 真实断链检查（以 lessons 目录为基准）====="
BAD=0; TOT=0
while IFS= read -r link; do
  TOT=$((TOT+1))
  tgt="$B/${link%%#*}"
  if [ -f "$tgt" ]; then echo "  ✅ $link"
  else echo "  ❌ $link"; BAD=$((BAD+1)); fi
done < <(grep -oE '\]\(([^)]+\.md)\)' "$L8" | sed 's/](\(.*\))/\1/')
echo "  共 $TOT 条，真实断链 $BAD 条"

echo
echo "===== 2. 讲义引用的实测数字复测 ====="
echo "  --- 版本 ---"
echo "  实测: $(consul version 2>/dev/null | head -1)  (讲义: v2.0.2)"
echo "  --- 当前集群 ---"
echo "  进程数 = $(pgrep -fc 'consul agent' 2>/dev/null || echo 0)"

echo
echo "===== 3. 结构自检 ====="
echo "  行数: $(wc -l < "$L8")"
echo "  大小: $(wc -c < "$L8") 字节"
echo "  核心结论条数: $(sed -n '/## 四、本课核心结论/,/^## /p' "$L8" | grep -c '^[0-9]\.')"
echo "  小测题数: $(sed -n '/### 小测/,/<details>/p' "$L8" | grep -c '^[0-9]\.')"
echo "  未实测标注: $(grep -c '本机未实测\|未实测' "$L8")"
echo "  官方引用: $(grep -c 'developer.hashicorp.com\|github.com/hashicorp' "$L8")"
echo "  mermaid 块: $(grep -c '```mermaid' "$L8")"
