#!/usr/bin/env bash
ROOT=/mnt/d/projects/learning/prometheus
F8="$ROOT/stages/3-规模化与生态/lessons/lesson-08-联邦与全局视图.md"
echo "=== 1. 讲义文件 ==="
echo "  大小 = $(wc -c < "$F8") 字节，$(wc -l < "$F8") 行"
echo
echo "=== 2. 五幕结构 ==="
for h in 一、场景引入 二、认知冲突 三、层层揭示 四、实操验证 五、体系收束; do
  n=$(grep -c "^## $h" "$F8")
  [ "$n" -eq 1 ] && echo "  OK   $h" || echo "  BAD  $h ($n)"
done
echo
echo "=== 3. 课尾套件 ==="
for h in "本课小测" "本课速览" "课程导航" "接力提示词" "本课评审结论"; do
  n=$(grep -c "$h" "$F8")
  [ "$n" -ge 1 ] && echo "  OK   $h" || echo "  MISS $h"
done
echo
echo "=== 4. 四处档案回写 ==="
printf "  ① 档案 进度表课8✅行: "; grep -c '^| 3 | 课 8 | .* | ✅ 已完成 |' "$ROOT/00-学习档案.md"
printf "  ① 档案 课8事实核查:   "; grep -c '^| 2026-09-07 |' "$ROOT/00-学习档案.md"
printf "  ② 评审清单 勾选:      "; grep -c '^- \[x\] 阶段 3·课 8' "$ROOT/00-评审清单.md"
printf "  ② 评审清单 记录行:    "; grep -c '^| 2026-09-07 | 课 8《联邦与全局视图》' "$ROOT/00-评审清单.md"
printf "  ③ 阶段overview 产出:  "; grep -c '^- \[x\] `lessons/lesson-08' "$ROOT/stages/3-规模化与生态/overview.md"
printf "  ③ 阶段overview 结论:  "; grep -c '课 8 完成情况' "$ROOT/stages/3-规模化与生态/overview.md"
printf "  ④ 02-课程目录:        "; grep -c '^| 8 | 联邦与全局视图 | .* | ✅ |' "$ROOT/02-课程目录.md"
printf "  ④ 01-路径总览:        "; grep -c '课 7 ✅、课 8 ✅ 已交付' "$ROOT/01-学习路径总览.md"
printf "  ④ 总进度:             "; grep -o '\*\*[0-9]*/36 知识点\*\*' "$ROOT/01-学习路径总览.md"
echo
echo "=== 5. 链接可达性 ==="
bash "$ROOT/labs/lesson-07/verify-links.sh" 2>&1 | grep '汇总'
