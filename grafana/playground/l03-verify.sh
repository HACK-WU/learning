#!/usr/bin/env bash
# 课 3 交付校验：结构合规（A 组）+ 引用文件存在性（B 组）+ 链接可达性
# 每条判定回读原文，避免凭记忆断言
set -u
cd /mnt/d/projects/learning/grafana
F="stages/1-看得见/lessons/lesson-03-变量与Dashboard组织：一张图服务N台机器.md"
FAIL=0
chk(){ if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; else echo "  ❌ $1"; FAIL=$((FAIL+1)); fi; }

echo "=========== A 组 · 结构合规 ==========="
chk "五幕：第一幕"        "grep -q '^## 第一幕' '$F'"
chk "五幕：第二幕"        "grep -q '^## 第二幕' '$F'"
chk "五幕：第三幕"        "grep -q '^## 第三幕' '$F'"
chk "五幕：第四幕"        "grep -q '^## 第四幕' '$F'"
chk "五幕：第五幕"        "grep -q '^## 第五幕' '$F'"
chk "课尾：本课速览"      "grep -q '^## 📌 本课速览' '$F'"
chk "课尾：评审结论"      "grep -q '^## 🔍 本课评审结论' '$F'"
chk "课尾：课程导航"      "grep -q '^## 🧭 课程导航' '$F'"
chk "课尾：接力提示词"    "grep -q '^## 🚀 下一批接力提示词' '$F'"

echo
echo "=========== A2 · 六要素（每知识点 6 项）==========="
for kp in "3.1" "3.2" "3.3"; do
  n=$(awk -v k="知识点 $kp" 'index($0,k){f=1} f&&/^#### /{print}' "$F" \
      | grep -cE '一句话定义|直觉建立|核心原理|示例演示|常见误区|一句话记住')
  if [ "$n" -ge 6 ]; then echo "  ✅ $kp 六要素齐全（$n/6）";
  else echo "  ❌ $kp 六要素缺失（$n/6）"; FAIL=$((FAIL+1)); fi
done

echo
echo "=========== A3 · 类比失效边界 ==========="
n=$(grep -c '类比的失效边界' "$F")
if [ "$n" -ge 3 ]; then echo "  ✅ 类比失效边界 $n 处（≥3）"; else echo "  ❌ 仅 $n 处（应 ≥3）"; FAIL=$((FAIL+1)); fi

echo
echo "=========== B 组 · 引用的脚本是否真实存在 ==========="
for s in $(grep -oE 'playground/l03-[a-z0-9-]+\.(sh|py)' "$F" | sort -u); do
  if [ -f "$s" ]; then echo "  ✅ $s"; else echo "  ❌ $s 不存在"; FAIL=$((FAIL+1)); fi
done

echo
echo "=========== B2 · 课尾导航链接可达性 ==========="
python3 - <<'PYEOF'
import re,os,sys
F="stages/1-看得见/lessons/lesson-03-变量与Dashboard组织：一张图服务N台机器.md"
base=os.path.dirname(F)
txt=open(F,encoding='utf-8').read()
bad=0
for m in re.finditer(r'\[([^\]]+)\]\((\.[^)]+)\)', txt):
    label,target=m.group(1),m.group(2)
    p=os.path.normpath(os.path.join(base,target))
    if not os.path.exists(p):
        print(f"  ❌ 死链: {label} -> {target}"); bad+=1
print(f"  {'✅ 全部可达' if bad==0 else f'❌ {bad} 条死链'}")
sys.exit(1 if bad else 0)
PYEOF
[ $? -ne 0 ] && FAIL=$((FAIL+1))

echo
echo "=========== B3 · 返回根目录链接层级（课 2 曾在此翻车）==========="
# 课 2 的正确写法是 ../../../（lesson 目录距根三层）
if grep -qE '\]\(\.\./\.\./\.\./00-学习档案\.md\)' "$F"; then
  echo "  ✅ 学习档案用了 ../../../（正确层级）"
else
  echo "  ❌ 学习档案未用 ../../../（在 lessons/ 下应为三级）"
  FAIL=$((FAIL+1))
fi
# 误用两级 ../../ 指向根目录文件 → 必为死链
if grep -qE '\]\(\.\./\.\./(00|01|02)-' "$F"; then
  echo "  ❌ 存在 ../../ 两级写法（在 lessons/ 下这是错的）"
  grep -nE '\]\(\.\./\.\./(00|01|02)-' "$F" | head -5
  FAIL=$((FAIL+1))
else
  echo "  ✅ 无 ../../ 两级误写"
fi

echo
echo "=========== 汇总 ==========="
if [ "$FAIL" -eq 0 ]; then echo "  🎉 0 阻塞项"; else echo "  ⚠️ $FAIL 项待处理"; fi
exit $FAIL
