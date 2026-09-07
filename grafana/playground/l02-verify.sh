#!/usr/bin/env bash
# 课 2 交付校验（双视角评审前先跑）
# A 组：结构完整性（必须在评审前确认骨架齐全）
# B 组：知识点六要素是否齐全（用【行号切片】而非 awk 区间，避免课 1 踩过的正则坑）
# C 组：课尾三段式
# D 组：正文引用的本地文件是否真实存在
set -u
DOC="/mnt/d/projects/learning/grafana/stages/1-看得见/lessons/lesson-02-第一个面板：从零到看得见.md"
BASE="/mnt/d/projects/learning/grafana"
FAIL=0

echo "=== A. 结构完整性 ==="
check_structure() {
  local name="$1" pat="$2"
  if grep -qE "$pat" "$DOC"; then echo "  ✅ $name"; else echo "  ❌ $name"; FAIL=$((FAIL+1)); fi
}
check_structure "标题"            '^# 第 2 课：'
check_structure "🎯 本课目标"      '^## 🎯 本课目标'
check_structure "知识点导航表"      '^## 知识点导航'
check_structure "第一幕"          '^## 第一幕：'
check_structure "第二幕"          '^## 第二幕：'
check_structure "第三幕"          '^## 第三幕：'
check_structure "第四幕"          '^## 第四幕：'
check_structure "第五幕"          '^## 第五幕：'
check_structure "🐞 误区速查"      '^## 🐞 误区速查'
check_structure "📚 官方文档"      '^## 📚 官方文档'
check_structure "📌 本课速览"      '^## 📌 本课速览'
check_structure "🧭 课程导航"      '^## 🧭 课程导航'
check_structure "🚀 接力提示词"    '^## 🚀 下一批接力提示词'

echo
echo "=== B. 知识点六要素（每个知识点 6 项小标题）==="
# 课 1 教训：awk 区间正则 + 全角冒号都会导致误判，此处改用行号切片
for kp in 2.1 2.2 2.3; do
  start=$(grep -nE "^### 知识点 ${kp}([^0-9]|$)" "$DOC" | head -1 | cut -d: -f1)
  if [ -z "$start" ]; then
    echo "  ❌ 未找到知识点 ${kp} 的标题"; FAIL=$((FAIL+1)); continue
  fi
  total=$(wc -l < "$DOC")
  seg=$(sed -n "${start},${total}p" "$DOC" | grep -nE '^### 知识点 ' | sed -n '2p' | cut -d: -f1)
  if [ -n "$seg" ]; then
    end=$((start + seg - 2))
  else
    end=$total
  fi
  body=$(sed -n "${start},${end}p" "$DOC")
  miss=""
  for e in "一句话定义" "直觉建立" "核心原理" "示例演示" "常见误区" "一句话记住"; do
    echo "$body" | grep -qF "#### ${e}" || miss="$miss $e"
  done
  if [ -z "$miss" ]; then
    echo "  ✅ 知识点 ${kp} 六要素齐全（行 ${start}-${end}）"
  else
    echo "  ❌ 知识点 ${kp} 缺失:${miss}（行 ${start}-${end}）"; FAIL=$((FAIL+1))
  fi
done

echo
echo "=== C. 课尾三段式 + 导航三列表 ==="
if grep -qF '| 上一课 | 本课 | 下一课 |' "$DOC"; then echo "  ✅ 导航三列表"; else echo "  ❌ 导航三列表"; FAIL=$((FAIL+1)); fi
if grep -qF '继续学 Grafana。我的学习档案在 grafana/00-学习档案.md' "$DOC"; then echo "  ✅ 接力提示词"; else echo "  ❌ 接力提示词"; FAIL=$((FAIL+1)); fi

echo
echo "=== D. 正文引用的本地文件是否存在 ==="
for rel in \
  "playground/l00-env-up.sh" \
  "playground/l02-init.sh" \
  "playground/l02-init2.sh" \
  "playground/l02-timing.sh" \
  "playground/l02-ds.sh" \
  "playground/l02-cors2.sh" \
  "playground/l02-cors.sh" \
  "playground/l02-panel.py" \
  "playground/l02-panel-diag.sh"; do
  if [ -f "${BASE}/${rel}" ]; then echo "  ✅ ${rel}"; else echo "  ❌ ${rel} 不存在"; FAIL=$((FAIL+1)); fi
done
for rel in \
  "stages/1-看得见/lessons/lesson-01-Grafana是谁：一个不存数据的看图工具.md" \
  "stages/1-看得见/lessons/lesson-03-变量与Dashboard组织：一张图服务N台机器.md" \
  "stages/1-看得见/overview.md" \
  "02-课程目录.md" \
  "00-学习档案.md"; do
  if [ -f "${BASE}/${rel}" ]; then echo "  ✅ ${rel}"; else echo "  ❌ ${rel} 不存在"; FAIL=$((FAIL+1)); fi
done

echo
echo "=== E. 字数与规模 ==="
echo "  行数: $(wc -l < "$DOC")"
echo "  字节: $(wc -c < "$DOC")"

echo
echo "RESULT: ${FAIL} 阻塞项"
