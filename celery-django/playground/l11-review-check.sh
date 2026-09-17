#!/usr/bin/env bash
# Phase 5 评审自检：机械性检查（引用一致性、结构完整性、链接可达）
set -u
BASE=/mnt/d/projects/learning/celery-django
cd "$BASE" || exit 1

echo "############ 1. 三份文件的故障模式编号一致性 ############"
echo "--- 08 里的故障模式标题 ---"
grep -oE '^### 故障模式 [0-9]+ · .*' 08-实战经验.md
echo
echo "--- 09 索引表里引用的编号 ---"
grep -oE '#[0-9]+ · ' 09-排障速查手册.md | sort -u
echo
echo "--- 09 里实际存在的条目标题 ---"
grep -oE '^## [0-9]+ · .*' 09-排障速查手册.md

echo
echo "############ 2. 10 里的「原理」回指编号 ############"
grep -rhoE '故障模式 [0-9]+' 10-场景解法库/ | sort | uniq -c

echo
echo "############ 3. 锚点链接是否可达（09 索引表）############"
# 提取索引表里的锚点
grep -oE '\(#[0-9]+-[a-z0-9-]+\)' 09-排障速查手册.md | tr -d '()#' | sort -u > /tmp/anchors_used.txt
# 从标题生成实际锚点（GitHub 风格：小写、空格转-、去标点）
grep -E '^## [0-9]+ · ' 09-排障速查手册.md | sed 's/^## //' > /tmp/anchors_actual_raw.txt
echo "--- 索引用到的锚点 ---"
cat /tmp/anchors_used.txt
echo
echo "--- 实际标题（转锚点后）---"
while IFS= read -r line; do
  anchor=$(echo "$line" | tr '[:upper:]' '[:lower:]' | sed 's/ · /-/g; s/ /-/g; s/[()（）·.,，]//g')
  echo "$anchor"
done < /tmp/anchors_actual_raw.txt | sort -u > /tmp/anchors_actual.txt
cat /tmp/anchors_actual.txt

echo
echo "--- 差异（左边=用到但没有的，右边=有但没用到的）---"
diff /tmp/anchors_used.txt /tmp/anchors_actual.txt && echo "✅ 锚点完全一致" || echo "⚠️ 有差异，见上"

echo
echo "############ 4. 跨文件链接可达性 ############"
for f in 08-实战经验.md 09-排障速查手册.md 10-场景解法库/INDEX.md 应用实战/INDEX.md; do
  d=$(dirname "$f")
  echo "--- $f ---"
  grep -oE '\]\(\.\.?/[^)]+\)' "$f" | sed 's/](\(.*\))/\1/' | sort -u | while read -r link; do
    target=$(echo "$link" | sed 's/#.*//')
    if [ -z "$target" ]; then continue; fi
    if [ -e "$d/$target" ]; then
      echo "  ✅ $link"
    else
      echo "  ❌ $link (不存在)"
    fi
  done
done

echo
echo "############ 5. 场景解法库硬要求检查（目录形态）############"
echo "场景文件数: $(ls 10-场景解法库/场景-*.md 2>/dev/null | wc -l)"
echo "每个场景的必备块（按文件逐一核对）:"
for sf in 10-场景解法库/场景-*.md; do
  n=$(basename "$sf" .md)
  printf "  %-28s" "$n"
  printf " 先想:%s" "$(grep -c '🔒 先自己想\|🔒 \*\*先自己想\*\*' "$sf")"
  printf " 提示:%s" "$(grep -c 'summary>💡 提示' "$sf")"
  printf " 展开:%s" "$(grep -c 'summary>📖 展开解法' "$sf")"
  printf " 挂钩:%s" "$(grep -c '知识点挂钩' "$sf")"
  printf " 边界:%s" "$(grep -c '不适用\|什么情况下此方案不适用' "$sf")"
  printf " 路径:%s" "$(grep -c '推荐路径' "$sf")"
  printf " 非本栈:%s" "$(grep -c '非本栈替代路线' "$sf")"
  printf " 对比:%s" "$(grep -c '效果对比' "$sf")"
  echo
done
echo
echo "解法条目总数（解法一览表格行数）:"
grep -rhoE '^\| \*\*[A-E] · ' 10-场景解法库/ | wc -l

echo
echo "############ 6. 手册五特征检查 ############"
echo "  ① 开头索引表: $(grep -c '症状索引表' 09-排障速查手册.md)"
echo "  ② 一眼识别: $(grep -c '\*\*一眼识别\*\*' 09-排障速查手册.md)"
echo "  ③ 止血优先(每条首行): $(grep -cE '^\| \*\*止血\*\*' 09-排障速查手册.md)"
echo "  ④ 条件-动作表: $(grep -cE '^\| 步骤 \| 动作 \| 预期 \|' 09-排障速查手册.md)"
echo "  ⑤ 升级出口(若无效): $(grep -c '若无效' 09-排障速查手册.md)"
echo "  紧急度分级: $(grep -c '🔴\|🟡\|⚪' 09-排障速查手册.md)"

echo
echo "############ 7. 证据标注统计 ############"
echo "08 里:"
echo "  【实测】: $(grep -c '【实测】' 08-实战经验.md)"
echo "  【官方】: $(grep -c '【官方】' 08-实战经验.md)"
echo "  【公认】: $(grep -c '【公认】' 08-实战经验.md)"
echo "  ⏳ 置信度: $(grep -c '⏳ 置信度' 08-实战经验.md)"

exit 0
