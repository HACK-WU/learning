#!/usr/bin/env bash
# VM 课 0 定论二：刷盘后 query 仍查不到的真正原因 —— 缓存 or 陈旧窗口(staleness/lookback)?
set -u
BASE="http://localhost:8428"

echo "############ 实验 A：单个孤立样本 ############"
A="iso_probe_$RANDOM"
NOW=$(date +%s)
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" --data-binary "${A}{job=\"x\"} 1 ${NOW}"
curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
sleep 3

for OFF in 0 1 5 30 120 300; do
  T=$((NOW + OFF))
  R1=$(curl -s -m 10 --data-urlencode "query=${A}" --data-urlencode "time=${T}" "$BASE/api/v1/query" \
       | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  R2=$(curl -s -m 10 --data-urlencode "query=${A}" --data-urlencode "time=${T}" --data-urlencode "nocache=1" "$BASE/api/v1/query" \
       | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  echo "  time=样本时间+${OFF}s  默认查询=${R1} 条   nocache=1=${R2} 条"
done

echo
echo "############ 实验 B：连续样本（每 15 秒一个，共 8 个）############"
B="seq_probe_$RANDOM"
BASE_TS=$(date +%s)
for i in 0 1 2 3 4 5 6 7; do
  TS=$((BASE_TS - (7 - i) * 15))
  curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" --data-binary "${B}{job=\"x\"} ${i} ${TS}"
done
curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
sleep 3
echo "  最后样本时间 = ${BASE_TS}（= now）"
for OFF in 0 5 20 60 300; do
  T=$((BASE_TS + OFF))
  R1=$(curl -s -m 10 --data-urlencode "query=${B}" --data-urlencode "time=${T}" "$BASE/api/v1/query" \
       | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  echo "  time=最后样本+${OFF}s  默认查询=${R1} 条"
done

echo
echo "############ 实验 C：同一查询连续调用 3 次（看缓存是否自我修正）############"
C="cache_probe_$RANDOM"
NOW2=$(date +%s)
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" --data-binary "${C}{job=\"x\"} 7 ${NOW2}"
curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
sleep 3
for n in 1 2 3; do
  R=$(curl -s -m 10 --data-urlencode "query=${C}" "$BASE/api/v1/query" \
      | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))')
  echo "  第 ${n} 次默认查询 = ${R} 条"
  sleep 2
done

echo
echo "############ 实验 D：export 全程可见性对照 ############"
for M in "$A" "$B" "$C"; do
  N=$(curl -s -m 10 --data-urlencode "match[]=${M}" "$BASE/api/v1/export" | grep -c . )
  echo "  export ${M} = ${N} 条"
done

echo
echo "############ 实验 E：回滚缓存相关参数默认值 ############"
grep -A2 -E '^  -search\.(cacheTimestampOffset|disableAutoCacheReset|resetRollupResultCacheOnStartup|disableCache|maxStalenessInterval)' \
  /mnt/d/projects/learning/victoriametrics/playground/l00-flags-dump.txt
