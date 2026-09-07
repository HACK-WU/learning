#!/usr/bin/env bash
# 课 2 交付终检：把三道校验串起来跑一遍，确认最终状态
set -u
BASE="/mnt/d/projects/learning/grafana"
echo "############ 1. 结构 + 六要素 + 引用文件 ############"
bash "${BASE}/playground/l02-verify.sh" > /tmp/f1.txt 2>&1
grep -E '❌' /tmp/f1.txt && echo "  ↑ 存在阻塞项" || echo "  ✅ 无阻塞项"
grep 'RESULT' /tmp/f1.txt

echo
echo "############ 2. 链接可达性 ############"
bash "${BASE}/playground/l02-linkcheck.sh" > /tmp/f2.txt 2>&1
n=$(grep -c '❌' /tmp/f2.txt)
echo "  缺失链接数: $n"
[ "$n" = "0" ] && echo "  ✅ 全部可达" || grep '❌' /tmp/f2.txt

echo
echo "############ 3. .gitignore 规则生效 ############"
bash "${BASE}/playground/l02-ignore-verify.sh" > /tmp/f3.txt 2>&1
grep 'RESULT' /tmp/f3.txt

echo
echo "############ 4. 修复后的就绪判据 ############"
bash "${BASE}/playground/l02-readyfix.sh" > /tmp/f4.txt 2>&1
grep -E '旧判据|新判据' /tmp/f4.txt

echo
echo "############ 5. 档案回写核查（四处）############"
echo -n "  00-学习档案.md 进度        : "; grep -oE '\*\*进度统计\*\*：[0-9]+ / 36' "${BASE}/00-学习档案.md"
echo -n "  00-学习档案.md 有课 2 记录 : "; grep -c '课 2《第一个面板》' "${BASE}/00-学习档案.md"
echo -n "  00-评审清单.md 课 2 已勾选 : "; grep -c '\- \[x\] 阶段 1·课 2' "${BASE}/00-评审清单.md"
echo -n "  02-课程目录.md 课 2 已链接 : "; grep -c 'lesson-02-第一个面板：从零到看得见.md)' "${BASE}/02-课程目录.md"
echo -n "  01-学习路径总览.md 进度    : "; grep -oE '总进度\*\*：[0-9]+ / 36' "${BASE}/01-学习路径总览.md"
echo -n "  阶段 1 overview 课 2 已勾选: "; grep -c 'lesson-02-第一个面板：从零到看得见.md`（2026-09-04 交付' "${BASE}/stages/1-看得见/overview.md"

echo
echo "############ 6. 讲义规模 ############"
L="${BASE}/stages/1-看得见/lessons/lesson-02-第一个面板：从零到看得见.md"
echo "  行数: $(wc -l < "$L")"
echo "  字节: $(wc -c < "$L")"
echo
echo "FINAL CHECK DONE"
