#!/usr/bin/env bash
# 课 7 交付前结构校验（沿用 l06-verify.sh，适配课 7）
set -u

F="/mnt/d/projects/learning/grafana/stages/3-叫得醒/lessons/lesson-07-告警架构：规则在哪求值、状态怎么迁移.md"
BLOCK=0

echo "=========================================================="
echo " 课 7 交付前校验"
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
for kp in "7.1" "7.2" "7.3"; do
  n=$(awk -v kp="$kp" '
    $0 ~ ("知识点 " kp) {inblock=1}
    inblock && /^#### (一句话定义|直觉建立|核心原理|示例演示|常见误区|一句话记住)/ {c++}
    inblock && /^### 知识点 7\.[23]/ && $0 !~ ("知识点 " kp) {inblock=0}
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

echo -n "C3 上一课链接指向阶段 2（跨阶段用 ../../）："
if grep -q '(\.\./\.\./2-查得到/lessons/lesson-06' "$F"; then
  echo " ✓"
else
  echo " ✗"
  BLOCK=$((BLOCK+1))
fi

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
done < <(grep -o 'l07[-_][a-z0-9_]*\.\(sh\|py\)' "$F" | sort -u)
echo "  缺失 $MISSING 个"
[ "$MISSING" -eq 0 ] || BLOCK=$((BLOCK+1))

# ---------- E 组：事实自洽 ----------
echo ""
echo "--- [E] 关键事实自洽 ---"

echo -n "E1 端口统一（9201，不应出现 9091 端口误用）："
if grep -q 'localhost:9091' "$F"; then
  n=$(grep -c 'localhost:9091' "$F")
  echo " $n 处（9091 是 pushgateway，仅在实验记录中提及属正常）"
else
  echo " ✓ 未出现"
fi

echo -n "E2 关键数字（60.1/10.0/55.1/6种状态/1空帧0点）："
for n in "60.1" "10.0" "55.1" "1 空帧 0 点" "6 种"; do
  if grep -q "$n" "$F"; then echo -n "$n✓ "; else echo -n "$n✗ "; BLOCK=$((BLOCK+1)); fi
done
echo ""

echo -n "E3 KeepLast 拼写正确（应为 KeepLast 非 KeepLastState）："
if grep -q '`KeepLast`' "$F"; then echo " ✓"; else echo " ✗"; BLOCK=$((BLOCK+1)); fi

echo -n "E4 修正概览的表述是否写明："
c=$(grep -c '修正阶段 3 概览\|修正了阶段 3' "$F")
echo " $c 处"
[ "$c" -ge 1 ] || BLOCK=$((BLOCK+1))

echo -n "E5 「未实测/未触发/待补测」标注："
c=$(grep -cE '未实测|未触发|没有实际触发|课 8 若遇到|尚未' "$F")
echo " $c 处"

echo -n "E6 跨课收束（Grafana 揽活）："
c=$(grep -c '揽到自己身上\|第四次' "$F")
echo " $c 处"

echo -n "E7 环境恢复提示（停容器脚本）："
c=$(grep -c '自动恢复\|docker start grafana-node3' "$F")
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
