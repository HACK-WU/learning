#!/usr/bin/env bash
# 课 7 落盘终检：确认讲义 / SVG / 档案 / 目录四处一致
source "$(dirname "$0")/l7-env.sh"
set -u

BASE="/mnt/d/projects/learning/rabbitmq"
echo "产物根目录: $BASE"
echo ""

echo "=== 1. 讲义文件 ==="
L7="$BASE/stages/3-可靠性与投递语义/lessons/lesson-07-持久化与死信.md"
if [ -f "$L7" ]; then
  echo "  ✅ 存在，$(wc -l < "$L7") 行，$(stat -c%s "$L7") 字节"
else
  echo "  ❌ 缺失"
fi

echo ""
echo "=== 2. 讲义五幕结构 ==="
grep -c "^## 第.幕" "$L7" >/dev/null 2>&1
for act in "第一幕" "第二幕" "第三幕" "第四幕" "第五幕"; do
  if grep -q "^## ${act}" "$L7"; then
    echo "  ✅ ${act}"
  else
    echo "  ❌ ${act} 缺失"
  fi
done

echo ""
echo "=== 3. 知识点六要素（每个知识点应含一句话定义/直觉建立/核心原理/示例演示/常见误区）==="
for kp in "三层持久化" "持久化的真实程度" "TTL 与死信队列"; do
  echo "  【$kp】"
  grep -A200 "### 知识点" "$L7" | grep -E "^(#### 一句话定义|#### 直觉建立|#### 核心原理|#### 示例演示|#### 🐞 常见误区)" \
    | head -5 | sed 's/^/    /'
done

echo ""
echo "=== 4. SVG 资源 ==="
SVG="$BASE/stages/3-可靠性与投递语义/assets/lesson-07-persistence-deadletter.svg"
if [ -f "$SVG" ]; then
  echo "  ✅ 存在，$(stat -c%s "$SVG") 字节"
  grep -q "课 7" "$SVG" && echo "  ✅ 内容含本课标识"
else
  echo "  ❌ 缺失"
fi

echo ""
echo "=== 5. 讲义引用 SVG 的路径正确性（lesson 在 lessons/ 下，应为 ../assets/）==="
grep -oE '\]\(\.\.?/[^)]*\.svg\)' "$L7" | sed 's/^/  /'

echo ""
echo "=== 6. 跨文件档案 ==="
for f in "00-学习档案.md" "00-评审清单.md" "02-课程目录.md" \
         "stages/3-可靠性与投递语义/overview.md"; do
  p="$BASE/$f"
  if [ -f "$p" ]; then
    if grep -q "课 7" "$p" 2>/dev/null; then
      echo "  ✅ $f 已含课 7 记录"
    else
      echo "  ⚠️  $f 存在但未提及课 7"
    fi
  else
    echo "  ❌ $f 缺失"
  fi
done

echo ""
echo "=== 7. 评审清单勾选状态 ==="
grep "课 7《持久化与死信》" "$BASE/00-评审清单.md" | sed 's/^/  /'

echo ""
echo "=== 8. 课程目录课 7 条目 ==="
grep -A4 "课 7：持久化与死信" "$BASE/02-课程目录.md" | head -5 | sed 's/^/  /'

echo ""
echo "=== 9. 阶段概览产出清单 ==="
grep "lesson-07" "$BASE/stages/3-可靠性与投递语义/overview.md" | sed 's/^/  /'
