#!/bin/bash
# 课 7 交付前独立复验
# 铁律：每条判定先核验再写入；复验脚本必须原样照抄讲义，不得补全步骤
set -u
K=/mnt/d/projects/learning/kafka/kafka-python-client
L7="$K/stages/3-生产层-吞吐与可靠性/课7-吞吐调优与压缩.md"

echo "########## A：正文数字 vs 实测输出 一致性 ##########"
# 注意：正文表格用千分位写法（81,591），实测输出是裸数字（81591）。
# 核验时必须同时匹配两种形式，否则会产生"数字不存在"的假阴性。
check_num () {
  raw=$1
  # 千分位不依赖 locale：用 sed 从右往左每三位插逗号（纯整数才处理）
  if echo "$raw" | grep -qE '^[0-9]+$'; then
    pretty=$(echo "$raw" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
  else
    pretty="$raw"
  fi
  c1=$(grep -c -- "$raw" "$L7")
  c2=$(grep -c -- "$pretty" "$L7")
  total=$((c1 + c2))
  if [ "$total" -eq 0 ]; then
    printf "  \033[31m✗ %-10s 正文未出现\033[0m\n" "$raw"
  else
    printf "  ✓ %-10s 正文出现 %s 次\n" "$raw" "$total"
  fi
}

for n in 81591 103875 453499 472505 8301 8283 9319 \
         101677 8027 88662 28058 120232 32200 74516 35444 81790 33812 \
         152804 121410 72671 74144 3030 3472 3457 169963 123018 73593 \
         36115 8863 1136 368595 89185 12677; do
  check_num "$n"
done
for n in 13.88 9.72 11.37 14.32 0.87 0.98 0.82 0.96 \
         173.15 19.81 111.48 472.10 24.88 15.25 13.03 44.39 \
         4.41 8.66 8.88 44.99 87.09 99.04; do
  check_num "$n"
done

echo ""
echo "########## B：围栏结构 ##########"
awk '/^```/{n++} END{print "  代码围栏总数 = " n " (偶数即合法)"}' "$L7"
grep -c '^```mermaid' "$L7" | xargs -I{} echo "  mermaid 块 = {}"

echo ""
echo "########## C：链接可达性（相对路径逐个 stat）##########"
cd "$K/stages/3-生产层-吞吐与可靠性"
grep -oE '\]\(\.\.?/[^)]+\)' "$L7" | sed 's/^](//; s/)$//' | sort -u | while read -r p; do
  if [ -e "$p" ]; then echo "  ✓ $p"
  else echo "  ✗ 断链 $p"; fi
done

echo ""
echo "########## D：集群卫生（修正版工具）##########"
bash "$K/assets/bench/check_hygiene.sh" 2>&1

echo ""
echo "########## E：残留容器 ##########"
docker ps -a --filter name=bench --format '{{.Names}}' 2>/dev/null | head -5
docker ps -a --filter name=slow --format '{{.Names}}' 2>/dev/null | head -5
docker ps -a --filter name=diag --format '{{.Names}}' 2>/dev/null | head -5
echo "  (以上为空即无残留)"

echo ""
echo "########## F：库版本一致性（正文声称 3.0.11，实测）##########"
docker run --rm kafka-pybench:3.12 /app/.venv/bin/python -c \
  "import importlib.metadata as m; print('  kafka-python =', m.version('kafka-python')); print('  confluent-kafka =', m.version('confluent-kafka'))" 2>&1 | head -3
