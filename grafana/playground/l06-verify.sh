#!/usr/bin/env bash
# 课 6 交付前结构校验（沿用 l05-verify.sh，适配课 6）
set -u

F="/mnt/d/projects/learning/grafana/stages/2-查得到/lessons/lesson-06-变量进阶与动态仪表盘.md"
BLOCK=0

echo "=========================================================="
echo " 课 6 交付前校验"
echo "=========================================================="
echo "文件：$(basename "$F")"
echo "行数：$(wc -l < "$F")  字节：$(wc -c < "$F")"
echo ""

# ---------- A 组：结构合规 ----------
echo "--- [A] 结构合规 ---"

echo -n "A1 五幕结构："
for s in "第一幕：场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束"; do
  if grep -q "$s" "$F"; then echo -n "✓"; else echo -n "✗($s) "; BLOCK=$((BLOCK+1)); fi
done
echo ""

echo -n "A2 课尾三段式："
for s in "## 📌 本课速览" "## 🧭 课程导航" "## 🚀 下一批接力提示词"; do
  if grep -q "$s" "$F"; then echo -n "✓"; else echo -n "✗($s) "; BLOCK=$((BLOCK+1)); fi
done
echo ""

echo "A3 六要素逐知识点统计："
for kp in "6.1" "6.2" "6.3"; do
  n=$(awk -v kp="$kp" '
    $0 ~ ("知识点 " kp) {inblock=1}
    inblock && /^#### (一句话定义|直觉建立|核心原理|示例演示|常见误区|一句话记住)/ {c++}
    inblock && /^### 知识点 6\.[23]/ && $0 !~ ("知识点 " kp) {inblock=0}
    inblock && /^## 🛠 第四幕/ {inblock=0}
    END {print c+0}
  ' "$F")
  if [ "$n" -ge 6 ]; then
    echo "    $kp → $n 项 ✓"
  else
    echo "    $kp → $n 项 ✗（应至少 6）"
    BLOCK=$((BLOCK+1))
  fi
done

echo -n "A4 类比失效边界（应 ≥3）："
n=$(grep -c '类比失效的边界' "$F")
echo " $n 处"
[ "$n" -ge 3 ] || BLOCK=$((BLOCK+1))

echo -n "A5 Mermaid 图："
n=$(grep -c '```mermaid' "$F")
echo " $n 个"
[ "$n" -ge 2 ] || { echo "    ✗ 应至少 2 个"; BLOCK=$((BLOCK+1)); }

# ---------- B 组：命令写法（课 4 P0 教训）----------
echo ""
echo "--- [B] 命令写法（PowerShell 兼容）---"

BAD=$(awk '/^```/{inblk=!inblk; next} !inblk && /wsl -d Ubuntu -- bash -lc +\\$/{c++} END{print c+0}' "$F")
GOOD=$(grep -c 'wsl -d Ubuntu -- bash -lc "' "$F")
echo "  单行写法：$GOOD 处"
echo "  代码块外的反斜杠续行：$BAD 处"
if [ "$BAD" -eq 0 ]; then
  echo "  ✓ 无续行缺陷（课 4 P0 未复发）"
else
  echo "  ✗ 有 $BAD 处续行，PowerShell 会失败"
  BLOCK=$((BLOCK+1))
fi

# ---------- C 组：链接可达性 ----------
echo ""
echo "--- [C] 链接可达性 ---"

DEAD=0
TOTAL=0
while IFS= read -r line; do
  link=$(echo "$line" | sed -n 's/.*](\([^)]*\)).*/\1/p')
  [ -z "$link" ] && continue
  case "$link" in
    http*) continue ;;
  esac
  TOTAL=$((TOTAL+1))
  target="$(dirname "$F")/$link"
  if [ ! -f "$target" ]; then
    echo "  ✗ 死链：$link"
    DEAD=$((DEAD+1))
  fi
done < <(grep -o '\[[^]]*\]([^)]*)' "$F")

echo "  共 $TOTAL 条本地链接，死链 $DEAD 条"
[ "$DEAD" -eq 0 ] || BLOCK=$((BLOCK+1))

echo -n "C2 返回根目录用 ../../../："
n=$(grep -c '\.\./\.\./\.\./' "$F")
echo " $n 处"
[ "$n" -ge 3 ] || { echo "    ✗ 应至少 3 条"; BLOCK=$((BLOCK+1)); }

# ---------- D 组：脚本存在性 ----------
echo ""
echo "--- [D] 正文引用的脚本是否真实存在 ---"
ROOT=/mnt/d/projects/learning/grafana
MISSING=0
while IFS= read -r s; do
  [ -z "$s" ] && continue
  if [ -f "$ROOT/playground/$s" ]; then
    echo "  ✓ $s"
  else
    echo "  ✗ 缺失：$s"
    MISSING=$((MISSING+1))
  fi
done < <(grep -o 'l06[-_][a-z0-9_]*\.\(sh\|py\)' "$F" | sort -u)
echo "  缺失 $MISSING 个"
[ "$MISSING" -eq 0 ] || BLOCK=$((BLOCK+1))

# ---------- E 组：事实自洽 ----------
echo ""
echo "--- [E] 关键事实自洽 ---"

echo -n "E1 端口统一 9201："
if grep -q '9091' "$F"; then
  echo ""
  grep -n '9091' "$F" | head -3 | sed 's/^/    /'
  BLOCK=$((BLOCK+1))
else
  echo " ✓"
fi

echo -n "E2 关键数字（21/42/480/21.8/4帧vs3帧）："
for n in "21" "42" "480" "21.8"; do
  if grep -q "$n" "$F"; then echo -n "$n✓ "; else echo -n "$n✗ "; BLOCK=$((BLOCK+1)); fi
done
echo ""

echo -n "E3 修正课 4 的两处是否写明："
c=$(grep -c '修正课 4\|课 4 说「语法错' "$F")
echo " $c 处"
[ "$c" -ge 1 ] || BLOCK=$((BLOCK+1))

echo -n "E4 「未实测/推算/依赖环境」标注："
c=$(grep -cE '推算值|未在真实|取决于你的|留给你|未演示|⚠️' "$F")
echo " $c 处"

echo -n "E5 跨课原则收束（存后端跑前端）："
c=$(grep -c '存后端' "$F")
echo " $c 处"

# ---------- 汇总 ----------
echo ""
echo "=========================================================="
if [ "$BLOCK" -eq 0 ]; then
  echo " ✅ 校验通过：0 阻塞项"
else
  echo " ❌ 检出 $BLOCK 项阻塞问题"
fi
echo "=========================================================="
exit $BLOCK
