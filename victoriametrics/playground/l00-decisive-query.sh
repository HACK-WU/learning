#!/usr/bin/env bash
# VM 课 0 决定性实验：为什么 export 能看到、query 看不到？逐变量排除
set -u
BASE="http://localhost:8428"

echo "=== 前置：确认容器与宿主机时钟一致 ==="
echo -n "container_now="; docker exec vm-learn date +%s
echo -n "wsl_now      ="; date +%s

TS=$(date +%s)
M="decisive_probe"
echo
echo "=== 写入样本：${M}，时间戳 ${TS}（秒）==="
curl -s -m 10 -o /dev/null -X POST "$BASE/api/v1/import/prometheus" \
  --data-binary "${M}{job=\"d\"} 123 ${TS}"
curl -s -m 10 -o /dev/null "$BASE/internal/force_flush"
sleep 3

echo
echo "--- 变量 1：默认时间瞬时查询 ---"
curl -s -m 10 --data-urlencode "query=${M}" "$BASE/api/v1/query"; echo

echo
echo "--- 变量 2：显式 time = 样本时间 + 60s ---"
curl -s -m 10 --data-urlencode "query=${M}" --data-urlencode "time=$((TS + 60))" "$BASE/api/v1/query"; echo

echo
echo "--- 变量 3：query_range，窗口 [ts-300, ts+300] ---"
curl -s -m 10 --data-urlencode "query=${M}" \
  --data-urlencode "start=$((TS - 300))" --data-urlencode "end=$((TS + 300))" \
  --data-urlencode "step=60" "$BASE/api/v1/query_range"; echo

echo
echo "--- 变量 4：nocache=1 ---"
curl -s -m 10 --data-urlencode "query=${M}" --data-urlencode "nocache=1" "$BASE/api/v1/query"; echo

echo
echo "--- 变量 5：export（作为对照组）---"
curl -s -m 10 --data-urlencode "match[]=${M}" "$BASE/api/v1/export"

echo
echo "=== 等待 60 秒后再次默认查询 ==="
sleep 60
echo -n "now="; date +%s
curl -s -m 10 --data-urlencode "query=${M}" "$BASE/api/v1/query"; echo

echo
echo "=== 时钟差检查：样本时间 vs 当前时间 ==="
NOW2=$(date +%s)
echo "sample_ts=${TS}  now=${NOW2}  diff=$((NOW2 - TS)) 秒"

echo
echo "=== 关键自监控：search 相关 ==="
curl -s -m 10 "$BASE/metrics" | grep -E '^vm_search|^vm_(slow|cache)' | head -10

echo
echo "=== 容器时钟是否领先宿主机（时区/漂移）==="
docker exec vm-learn date -u '+container_utc=%Y-%m-%dT%H:%M:%S'
date -u '+wsl_utc     =%Y-%m-%dT%H:%M:%S'
