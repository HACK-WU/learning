#!/usr/bin/env bash
ROOT=/mnt/d/projects/learning/prometheus
F7="$ROOT/stages/3-规模化与生态/lessons/lesson-07-远程读写与Agent模式.md"
echo "=== 1. 讲义文件 ==="
echo "  大小 = $(wc -c < "$F7") 字节，$(wc -l < "$F7") 行"
echo
echo "=== 2. 五幕结构 ==="
grep -c '^## 一、场景引入' "$F7" | sed 's/^/  第一幕 /'
grep -c '^## 二、认知冲突' "$F7" | sed 's/^/  第二幕 /'
grep -c '^## 三、层层揭示' "$F7" | sed 's/^/  第三幕 /'
grep -c '^## 四、实操验证' "$F7" | sed 's/^/  第四幕 /'
grep -c '^## 五、体系收束' "$F7" | sed 's/^/  第五幕 /'
echo
echo "=== 3. 课尾三件套 ==="
for h in "本课小测" "本课速览" "课程导航" "接力提示词" "本课评审结论"; do
  n=$(grep -c "$h" "$F7")
  [ "$n" -ge 1 ] && echo "  OK   $h" || echo "  MISS $h"
done
echo
echo "=== 4. 四处档案回写 ==="
printf "  ① 00-学习档案.md 进度表: "; grep -c '^| 3 | 课 7 | .* | ✅ 已完成 |' "$ROOT/00-学习档案.md"
printf "  ① 事实核查新增条数: "; grep -c '2026-09-04 | .*remote write\|2026-09-04 | .*Agent\|2026-09-04 | .*VictoriaMetrics\|2026-09-04 | .*external_labels\|2026-09-04 | .*bind mount' "$ROOT/00-学习档案.md"
printf "  ② 00-评审清单.md 勾选: "; grep -c '^- \[x\] 阶段 3·课 7' "$ROOT/00-评审清单.md"
printf "  ② 评审记录表课7行: "; grep -c '^| 2026-09-04 | 课 7《远程读写与 Agent 模式》' "$ROOT/00-评审清单.md"
printf "  ③ 阶段 overview 产出勾选: "; grep -c '^- \[x\] `lessons/lesson-07' "$ROOT/stages/3-规模化与生态/overview.md"
printf "  ③ 阶段 overview 完成情况: "; grep -c '课 7 完成情况' "$ROOT/stages/3-规模化与生态/overview.md"
printf "  ④ 02-课程目录.md: "; grep -c '^| 7 | 远程读写与 Agent 模式 | .* | ✅ |' "$ROOT/02-课程目录.md"
printf "  ④ 01-学习路径总览.md: "; grep -c '课 7 ✅ 已交付' "$ROOT/01-学习路径总览.md"
printf "  ④ 总进度: "; grep -o '\*\*[0-9]*/36 知识点\*\*' "$ROOT/01-学习路径总览.md"
echo
echo "=== 5. 链接可达性（上次结果 58 可达 / 0 死链）==="
bash "$ROOT/labs/lesson-07/verify-links.sh" 2>&1 | grep '汇总'
