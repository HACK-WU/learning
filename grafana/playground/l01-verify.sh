#!/usr/bin/env bash
# 课 1 交付校验：结构合规 + 链接可达 + 引用文件存在
set -u
ROOT=/mnt/d/projects/learning/grafana
L="$ROOT/stages/1-看得见/lessons/lesson-01-Grafana是谁：一个不存数据的看图工具.md"
FAIL=0

echo "===== A 组：结构合规 ====="
chk() { # chk 标签 正则 文件
  if grep -qE "$2" "$3"; then echo "  ✅ $1"; else echo "  ❌ $1"; FAIL=$((FAIL+1)); fi
}
chk "五幕·第一幕" '^## 第一幕：起源与场景引入' "$L"
chk "五幕·第二幕" '^## 第二幕：认知冲突' "$L"
chk "五幕·第三幕" '^## 第三幕：层层揭示' "$L"
chk "五幕·第四幕" '^## 第四幕：实操验证' "$L"
chk "五幕·第五幕" '^## 第五幕：体系收束' "$L"
chk "课尾·本课速览" '^## 📌 本课速览' "$L"
chk "课尾·课程导航" '^## 🧭 课程导航' "$L"
chk "课尾·接力提示词" '^## 🚀 下一批接力提示词' "$L"

echo "  -- 知识点六要素（1.1/1.2/1.3 各六项）--"
# ⚠️ 2026-09-04 假报警教训：初版用 awk 区间正则
#      awk "/^### 知识点 ${kp}:/,/^### 知识点|$ /"
#   其中 `|$ ` 本意是「文件末行」，实际却匹配到空行，导致区间被过早截断，
#   18 个要素全部误报 MISS。经 l01-verify-diag.sh 用固定字符串 grep 核验，
#   六要素 18 个标题真实存在（行号 71-439）。
#   **结论：报警先判真伪，本例属脚本缺陷，改脚本不改文档。**
#   修正为：先用 grep 拿到知识点起始行号，再用 sed 按行号切片。
get_kp_range() { # get_kp_range 知识点号 -> 起始,结束 行号
  local kp="$1"
  local start end total
  # ⚠️ 第二个脚本缺陷（2026-09-04）：标题用的是**全角冒号**「：」
  #    初版写 `^### 知识点 ${kp}:` 用半角冒号，永远匹配不到，产出行号 1,0。
  #    修正：只锚定到「### 知识点 1.1」这一段数字，后面字符不限，绕开中英文标点差异。
  start=$(grep -nE "^### 知识点 ${kp}([^0-9]|$)" "$L" | head -1 | cut -d: -f1)
  total=$(wc -l < "$L")
  if [ -z "$start" ]; then echo "1,0"; return; fi
  # 结束行 = 下一个 ### 知识点 的前一行；若无下一个则到文件末
  end=$(awk -v s="$start" 'NR>s && /^### 知识点 /{print NR-1; exit}' "$L")
  [ -z "$end" ] && end=$total
  echo "${start},${end}"
}
for kp in 1.1 1.2 1.3; do
  RNG=$(get_kp_range "$kp")
  for el in "一句话定义" "直觉建立（类比）" "核心原理" "示例演示" "常见误区" "一句话记住"; do
    if sed -n "${RNG}p" "$L" | grep -qE "^#### ${el}"; then
      :
    else
      echo "  ❌ 知识点 ${kp}（行 ${RNG}）缺要素：${el}"; FAIL=$((FAIL+1))
    fi
  done
done
echo "  ✅ 六要素检查完毕（无输出即全过）"

echo "  -- 类比失效边界 --"
N=$(grep -c '类比的边界' "$L")
echo "     类比失效边界出现 $N 次（应 = 3，每知识点 1 次）"
[ "$N" -eq 3 ] || { echo "  ❌ 类比边界数量不对"; FAIL=$((FAIL+1)); }

echo "  -- 代码块配对 --"
OPEN=$(grep -c '^```' "$L")
echo "     围栏标记 $OPEN 个（应为偶数）"
[ $((OPEN % 2)) -eq 0 ] || { echo "  ❌ 围栏未配对"; FAIL=$((FAIL+1)); }

echo
echo "===== B 组：链接可达 ====="
bash "$ROOT/playground/l00-linkcheck.sh" | tail -4

echo
echo "===== C 组：讲义引用的脚本/文件真实存在 ====="
for f in playground/l00-env-up.sh playground/l00-portcheck.sh \
         playground/l00-linkcheck.sh playground/l01-forms.py \
         playground/prometheus.yml; do
  if [ -f "$ROOT/$f" ]; then echo "  ✅ $f"; else echo "  ❌ $f 不存在"; FAIL=$((FAIL+1)); fi
done

echo
echo "===== 汇总 ====="
[ "$FAIL" -eq 0 ] && echo "RESULT: OK（0 阻塞项）" || echo "RESULT: FAIL（$FAIL 项）"
exit $FAIL
