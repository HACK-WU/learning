#!/usr/bin/env bash
# 课 9 双视角评审校验：结构完整性 + 知识点六要素 + 速览/小测 + 链接可达
set -uo pipefail
DOC=/mnt/d/projects/learning/prometheus/stages/3-规模化与生态/lessons/lesson-09-长期存储选型.md
ROOT=/mnt/d/projects/learning/prometheus
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  [FAIL] $1 ($2)"; }
chk(){ [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2!=$3"; }

echo "================ 视角一：pedagogy（教学结构）================"
for m in "第一幕：场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束"; do
  n=$(grep -c "$m" "$DOC")
  chk "五幕之 $m 存在" "$n" "1"
done

echo
echo "================ 视角一：三个知识点六要素 ================"
# 六要素：一句话定义 / 直觉建立 / 核心原理 / 示例演示 / 常见误区 / 一句话记住
for k in "知识点 1：三种架构路线" "知识点 2：选型决策框架" "知识点 3：与 OpenTelemetry"; do
  # 取该知识点到下一个同级标题之间的内容
  seg=$(awk -v k="$k" 'index($0,k){f=1} f{print} f&&/^### 知识点/&&!index($0,k){exit}' "$DOC")
  defs=$(echo "$seg" | grep -c '#### 一句话定义')
  intu=$(echo "$seg" | grep -c '#### 直觉建立')
  prin=$(echo "$seg" | grep -c '#### 核心原理')
  demo=$(echo "$seg" | grep -c '#### 示例演示')
  pitf=$(echo "$seg" | grep -c '#### 常见误区')
  remb=$(echo "$seg" | grep -c '#### 一句话记住')
  tot=$((defs+intu+prin+demo+pitf+remb))
  chk "$k 六要素齐全(6)" "$tot" "6"
done

echo
echo "================ 视角二：learner（学员可用性）================"
n=$(grep -c '## ⚡ 速览卡' "$DOC"); chk "速览卡存在" "$n" "1"
n=$(grep -c '## 📝 小测' "$DOC"); chk "小测存在" "$n" "1"
n=$(grep -c '## 🗺️ 课程导航' "$DOC"); chk "课程导航存在" "$n" "1"
n=$(grep -c '接力提示词' "$DOC"); chk "接力提示词存在" "$n" "1"

# 选择题/判断题/简答题数量
n=$(grep -cE '^\*\*[0-9]+\. ' "$DOC")
echo "  [INFO] 小测题目数: $n"
[ "$n" -ge 5 ] && ok "小测题目 >= 5" || bad "小测题目过少" "$n"

# 答案可展开
n=$(grep -c '<details>' "$DOC")
echo "  [INFO] 可展开答案块: $n"
[ "$n" -ge 5 ] && ok "答案块 >= 5" || bad "答案块过少" "$n"

echo
echo "================ 硬性约束：未实测标注 ================"
n=$(grep -c '【未实测' "$DOC")
echo "  [INFO] 【未实测】标注数: $n"
[ "$n" -ge 1 ] && ok "存在未实测标注（诚实披露）" || bad "缺少未实测标注" "$n"

echo
echo "================ 硬性约束：无（同上）类偷懒 ================"
for p in '（同上）' '（略）' '同上)' '列定义同上'; do
  n=$(grep -cF "$p" "$DOC")
  [ "$n" -eq 0 ] && ok "无偷懒写法「$p」" || bad "存在偷懒写法「$p」" "$n"
done

echo
echo "================ 链接可达性 ================"
dead=0
grep -oE '\]\(\.\.?[^)]+\.md\)' "$DOC" | sed 's/^](//; s/)$//' | sort -u | while read -r rel; do
  d=$(dirname "$DOC")
  target="$d/$rel"
  if [ ! -f "$target" ]; then echo "  [DEAD] $rel"; fi
done
echo "  (死链列表见上，无输出即全部可达)"

echo
echo "================ 汇总 ================"
echo "  PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "  ✅ 评审校验通过" || echo "  ❌ 有失败项"
