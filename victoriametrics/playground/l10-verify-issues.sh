#!/bin/bash
# 核验 Agent A/B 的四条问题
F='/mnt/d/projects/learning/victoriametrics/stages/4-怎么横向扩展/10-多租户与vmauth.md'

echo "=== 核验 B-P1：空租户 ID 是否真缺失 ==="
echo "-- 误区区中含『空』或『tenant 0』的行 --"
awk '/## 🐞 常见误区/,/## 🚀/' "$F" | grep -n '空\|tenant 0' | head -8
echo
echo "-- 误区第 3 条完整内容 --"
awk '/### 3\. 以为空租户 ID 会报错/,/### 4\./' "$F" | head -10

echo
echo "=== 核验 B-P2：src_paths / url_prefix 是否有解释 ==="
echo "-- src_paths 首次出现处的上下文 --"
grep -n 'src_paths' "$F" | head -3
echo
echo "-- 配置注释里是否解释了这两个字段 --"
grep -n -A2 '# 写入（Influx 行协议）' "$F" | head -5
echo
echo "-- 检查『客户端』『后端』等解释性词汇 --"
echo "  '客户端' 出现: $(grep -c '客户端' "$F") 次"
echo "  '后端'   出现: $(grep -c '后端' "$F") 次"
echo "  '原始请求路径' 出现: $(grep -c '原始请求路径' "$F") 次"
echo
echo "-- 配置要点说明段 --"
grep -n -B1 -A6 '配置要点' "$F" | head -12

echo
echo "=== 核验 A-P1：知识点 2 篇幅 ==="
awk '/### 知识点 2/,/### 知识点 3/' "$F" | wc -l
echo "  上个阈值 240，实际如上"
echo
echo "-- 三个知识点篇幅对比 --"
for k in 1 2 3; do
  n=$(awk "/### 知识点 $k/,/### 知识点 $((k+1))/" "$F" | wc -l)
  echo "  知识点 $k: $n 行"
done
