#!/bin/bash
# 课 8 交付前独立复验
# 铁律①：每条「缺失/错误/遗漏」判定先核验再写入，不凭记忆
# 铁律②：复验脚本必须原样照抄讲义文本，不得补全步骤
set -u
K=/mnt/d/projects/learning/kafka/kafka-python-client
L8="$K/stages/3-生产层-吞吐与可靠性/课8-事务与恰好一次.md"

echo "########## A：讲义代码块能否照抄执行（结构与语法）##########"
# 抽出讲义里两段可运行实现，做语法编译检查（不补全、不改写）
python3 - <<'PYEOF'
import re, sys, subprocess, tempfile, os
p = r"/mnt/d/projects/learning/kafka/kafka-python-client/stages/3-生产层-吞吐与可靠性/课8-事务与恰好一次.md"
src = open(p, encoding="utf-8").read()
blocks = re.findall(r"```python\n(.*?)```", src, re.S)
print(f"  python 代码块数 = {len(blocks)}")
for i, b in enumerate(blocks, 1):
    # 讲义代码块含 BOOTSTRAP / SRC_TOPIC / transform 等占位符，属正常（非自包含示例）
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False, encoding="utf-8") as f:
        f.write(b); tmp = f.name
    r = subprocess.run([sys.executable, "-m", "py_compile", tmp],
                       capture_output=True, text=True)
    status = "✓ 语法通过" if r.returncode == 0 else f"✗ 语法错误: {r.stderr.strip()[:90]}"
    print(f"  块{i}: {status}")
    os.unlink(tmp)
PYEOF

echo ""
echo "########## B：关键实测数字是否写入正文（千分位+裸数双形式）##########"
check_num () {
  raw=$1
  if echo "$raw" | grep -qE '^[0-9]+$'; then
    pretty=$(echo "$raw" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
  else
    pretty="$raw"
  fi
  c1=$(grep -c -- "$raw" "$L8"); c2=$(grep -c -- "$pretty" "$L8")
  t=$((c1 + c2))
  if [ "$t" -eq 0 ]; then printf "  \033[31m✗ %-10s 正文未出现\033[0m\n" "$raw"
  else printf "  ✓ %-10s 出现 %s 次\n" "$raw" "$t"; fi
}
for n in 35491 6830 3674 848 362 87 48.8 9.2 20.5 108.5 727 742 78 98 \
         8.1 9.7 5.3 1 2 5 10; do check_num "$n"; done

echo ""
echo "########## C：围栏结构 ##########"
awk '/^```/{n++} END{print "  围栏总数 = " n+0 " (偶数即合法)"}' "$L8"

echo ""
echo "########## D：链接可达性 ##########"
cd "$K/stages/3-生产层-吞吐与可靠性" || exit 1
broken=0
while IFS= read -r p; do
  if [ ! -e "$p" ]; then echo "  ✗ 断链: $p"; broken=$((broken+1)); fi
done < <(grep -oE '\]\(\.\.?/[^)]+\)' 课8-事务与恰好一次.md | sed 's/^](//; s/)$//' | sort -u)
echo "  断链数 = $broken（应为 0）"

echo ""
echo "########## E：overview 错误预设是否已更正 ##########"
if grep -q '此说法已被课 8 实测推翻' "$K/stages/3-生产层-吞吐与可靠性/overview.md"; then
  echo "  ✓ overview 已加更正说明"
else
  echo "  ✗ overview 仍残留错误预设"
fi
if grep -q '事务 EOS、Schema Registry 这三样是 librdkafka 独占能力' "$K/stages/3-生产层-吞吐与可靠性/overview.md"; then
  echo "  ✗ 错误原句仍在"
else
  echo "  ✓ 错误原句已移除"
fi

echo ""
echo "########## F：集群卫生 ##########"
bash "$K/assets/bench/check_hygiene.sh" 2>&1 | head -4
