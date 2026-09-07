#!/usr/bin/env bash
# 课 4 交付前结构校验（借鉴课 1/2/3 的 l0X-verify.sh，并修正 B3 的判空缺陷）
set -u

F="/mnt/d/projects/learning/grafana/stages/2-查得到/lessons/lesson-04-查询编辑器与数据源协议：一次查询的完整旅程.md"
ROOT="/mnt/d/projects/learning/grafana"
BLOCK=0

echo "=========================================================="
echo " 课 4 交付前校验"
echo "=========================================================="
echo "文件：$F"
echo "行数：$(wc -l < "$F")  字节：$(wc -c < "$F")"
echo ""

# ---------- A 组：结构合规 ----------
echo "--- [A] 结构合规 ---"

echo -n "A1 五幕结构："
for s in "第一幕：场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束"; do
  if grep -q "$s" "$F"; then echo -n "✓"; else echo -n "✗$s "; BLOCK=$((BLOCK+1)); fi
done
echo ""

echo -n "A2 课尾三段式："
for s in "## 📌 本课速览" "## 🧭 课程导航" "## 🚀 下一批接力提示词"; do
  if grep -q "$s" "$F"; then echo -n "✓"; else echo -n "✗($s) "; BLOCK=$((BLOCK+1)); fi
done
echo ""

echo "A3 六要素逐知识点统计："
for kp in "4.1" "4.2" "4.3"; do
  # 用 awk 定位该知识点的章节区间，避免跨段误统计
  n=$(awk -v kp="$kp" '
    $0 ~ ("知识点 " kp) {inblock=1}
    inblock && /^#### (一句话定义|直觉建立|核心原理|示例演示|常见误区|一句话记住)/ {c++}
    inblock && /^### 知识点 4\.[23]/ && $0 !~ ("知识点 " kp) {inblock=0}
    END {print c+0}
  ' "$F")
  if [ "$n" -ge 6 ]; then
    echo "    $kp → $n 项 ✓"
  else
    echo "    $kp → $n 项 ✗（应为 6）"
    BLOCK=$((BLOCK+1))
  fi
done

echo -n "A4 类比失效边界（3 处）："
n=$(grep -c '类比失效的边界' "$F")
echo "$n 处"
[ "$n" -ge 3 ] || BLOCK=$((BLOCK+1))

echo -n "A5 Mermaid 图："
n=$(grep -c '```mermaid' "$F")
echo "$n 个"

# ---------- B 组：链接可达性 ----------
echo ""
echo "--- [B] 链接可达性 ---"

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
    echo "     解析为：$target"
    DEAD=$((DEAD+1))
  fi
done < <(grep -o '\[[^]]*\]([^)]*)' "$F")

echo "  共 $TOTAL 条本地链接，死链 $DEAD 条"
[ "$DEAD" -eq 0 ] || BLOCK=$((BLOCK+1))

# ---------- C 组：层级写法（显式判定，修正课 3 的判空缺陷）----------
echo ""
echo "--- [C] 返回根目录链接的层级写法 ---"
echo "  目录深度参考：lessons/ → 1-2-3 → stages/ → grafana/"
echo "  从 stages/2-查得到/lessons/ 出发，回根目录需 ../../../"

LEVEL3=$(grep -c '\.\./\.\./\.\./' "$F")
LEVEL2_BAD=$(grep -n '\]\(\.\./\.\./[^/.]\)' "$F" | head -5)
echo "  三级写法 ../../../ 出现 $LEVEL3 次"

if [ "$LEVEL3" -ge 3 ]; then
  echo "  ✓ 已使用三级返回根目录"
else
  echo "  ✗ 缺少三级返回根目录的链接（应至少 3 条）"
  BLOCK=$((BLOCK+1))
fi

if [ -n "$LEVEL2_BAD" ]; then
  echo "  ⚠ 检出疑似两级误写："
  echo "$LEVEL2_BAD"
else
  echo "  ✓ 未检出两级误写"
fi

# ---------- D 组：引用脚本存在性 ----------
echo ""
echo "--- [D] 正文引用的脚本是否真实存在 ---"
MISSING=0
while IFS= read -r s; do
  [ -z "$s" ] && continue
  if [ -f "$ROOT/playground/$s" ]; then
    echo "  ✓ $s"
  else
    echo "  ✗ 缺失：$s"
    MISSING=$((MISSING+1))
  fi
done < <(grep -o 'l04[-_][a-z0-9_]*\.\(sh\|py\)' "$F" | sort -u)
echo "  缺失 $MISSING 个"
[ "$MISSING" -eq 0 ] || BLOCK=$((BLOCK+1))

# ---------- E 组：数据事实自洽 ----------
echo ""
echo "--- [E] 关键事实前后自洽 ---"

echo -n "E1 Prometheus 端口统一为 9201（不得出现 9091 作为本课端口）："
if grep -q '9091' "$F"; then
  hits=$(grep -n '9091' "$F" | head -3)
  echo ""
  echo "$hits"
  BLOCK=$((BLOCK+1))
else
  echo " ✓ 未出现 9091"
fi

echo -n "E2 数据源 uid 一致（afx7x6dx803y8e）："
c=$(grep -c 'afx7x6dx803y8e' "$F")
echo " $c 处"
[ "$c" -ge 1 ] || BLOCK=$((BLOCK+1))

echo -n "E3 版本号一致（13.2.1）："
c=$(grep -c '13\.2\.1' "$F")
echo " $c 处"

echo -n "E4 「未实测/推断」标注："
c=$(grep -cE '推断|待实测|无法自动化|边界.*推断' "$F")
echo " $c 处"

# ---------- 汇总 ----------
echo ""
echo "=========================================================="
if [ "$BLOCK" -eq 0 ]; then
  echo " ✅ 校验通过：0 阻塞项"
else
  echo " ❌ 检出 $BLOCK 项阻塞问题，需修复后交付"
fi
echo "=========================================================="
exit $BLOCK
