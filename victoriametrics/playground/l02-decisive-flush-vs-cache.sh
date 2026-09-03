#!/usr/bin/env bash
# 课 2 定论：区分「内存缓冲未刷盘」与「查询缓存」两个因素
# 2x2 设计：{不刷盘, 刷盘} x {普通查询, nocache 查询}
set -u
BASE="http://localhost:8428"

run() {
  local label="$1" do_flush="$2"
  local m="matrix_${RANDOM}"
  local now; now=$(date +%s)

  curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" \
    --data-binary "${m}{job=\"m\"} 1 ${now}"

  if [ "$do_flush" = "yes" ]; then
    curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
  fi
  sleep 2

  local q1 q2
  q1=$(curl -s -m 10 --data-urlencode "query=${m}" "$BASE/api/v1/query" \
       | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  q2=$(curl -s -m 10 --data-urlencode "query=${m}" --data-urlencode 'nocache=1' "$BASE/api/v1/query" \
       | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  echo "  ${label}  普通查询=${q1}  nocache=1=${q2}   (指标=${m})"

  # 第二次普通查询：缓存过期后是否恢复
  sleep 3
  local q3
  q3=$(curl -s -m 10 --data-urlencode "query=${m}" "$BASE/api/v1/query" \
       | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  echo "          3 秒后再次普通查询=${q3}"
}

echo "=== 2x2 对照实验（每组重复 2 轮）==="
for round in 1 2; do
  echo "--- 第 ${round} 轮 ---"
  run "不刷盘   " "no"
  run "调用刷盘 " "yes"
done

echo
echo "=== 补充：缓存参数的官方默认值 ==="
grep -A3 -E '^  -search\.(cacheTimestampOffset|disableAutoCacheReset|maxStalenessInterval)' \
  /mnt/d/projects/learning/victoriametrics/playground/l00-flags-dump.txt 2>/dev/null | head -20
