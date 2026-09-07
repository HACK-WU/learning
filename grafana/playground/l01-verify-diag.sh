#!/usr/bin/env bash
# 真伪判定：课 1 的六要素到底存不存在？
set -u
L="/mnt/d/projects/learning/grafana/stages/1-看得见/lessons/lesson-01-Grafana是谁：一个不存数据的看图工具.md"

echo "=== 1. 文件是否存在、多大 ==="
ls -lh "$L" | awk '{print "  "$5"  "$9}'

echo "=== 2. 所有 #### 开头的标题（原始 grep，不加任何正则扩展）==="
grep -n '^####' "$L" | cat

echo "=== 3. 所有 ### 开头的标题 ==="
grep -n '^###' "$L" | cat

echo "=== 4. 逐个要素：用固定字符串 grep -F 判定 ==="
for el in '一句话定义' '直觉建立（类比）' '核心原理' '示例演示' '常见误区' '一句话记住'; do
  N=$(grep -cF "$el" "$L")
  echo "  $el : $N 次"
done

echo "=== 5. 判定结论 ==="
echo "  若上面第 2 步能看到 18 个 #### 标题（3 知识点 × 6 要素），"
echo "  说明六要素齐备，l01-verify.sh 报的 18 条 FAIL 是脚本缺陷（awk 区间正则问题），"
echo "  属假报警，不改文档，改脚本。"
