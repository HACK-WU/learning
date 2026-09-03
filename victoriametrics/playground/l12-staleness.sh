#!/bin/bash
# 课 12 实验 32：坐实「单点样本查不到」—— staleness 机制（本课第四个反直觉发现）
set -u
cd /mnt/d/projects/learning/victoriametrics/playground
CLEAN=http://localhost:8458

echo "===== [1] 现象确认：数据在库里（export 有值）但 query 查不到 ====="
echo "-- export（证明数据已入库） --"
curl -s --data-urlencode 'match[]=l12_clean_probe' "$CLEAN/api/v1/export" | head -c 200; echo
echo "-- query（查不到） --"
curl -s --data-urlencode 'query=l12_clean_probe' "$CLEAN/api/v1/query" | head -c 150; echo

echo ""
echo "===== [2] 假设验证：staleness —— 单点样本在「当前时刻」被视为陈旧 ====="
echo "-- 用 time 参数回退到样本时间戳处查询 --"
TS=1788355007
curl -s --data-urlencode 'query=l12_clean_probe' --data-urlencode "time=$TS" "$CLEAN/api/v1/query" | head -c 250; echo
echo "-- 对照：回退到 1 小时后 --"
curl -s --data-urlencode 'query=l12_clean_probe' --data-urlencode "time=$((TS+3600))" "$CLEAN/api/v1/query" | head -c 250; echo

echo ""
echo "===== [3] 决定性实验：连续写入多个样本后是否能查到 ====="
echo "-- 连续写 10 个样本，间隔 1 秒 --"
for i in $(seq 1 10); do
  curl -s -o /dev/null -X POST --data-binary "l12_multi{job=\"l12\"} $i" "$CLEAN/api/v1/import/prometheus"
  sleep 1
done
sleep 2
echo "-- 查 l12_multi --"
curl -s --data-urlencode 'query=l12_multi' "$CLEAN/api/v1/query" | head -c 250; echo

echo ""
echo "===== [4] 对照：单点 vs 多点（决定性） ====="
echo "-- 单点（只写一个样本） --"
curl -s -o /dev/null -X POST --data-binary 'l12_single{job="l12"} 999' "$CLEAN/api/v1/import/prometheus"
sleep 2
echo "  l12_single 查询结果："
curl -s --data-urlencode 'query=l12_single' "$CLEAN/api/v1/query" | head -c 200; echo
echo "-- 用 max_lookback 参数强制放大回看窗口 --"
curl -s --data-urlencode 'query=l12_single' --data-urlencode 'max_lookback=1h' "$CLEAN/api/v1/query" | head -c 250; echo

echo ""
echo "===== [5] 用 -search.maxStalenessInterval 显式设置后重试 ====="
docker rm -f vm-stale-test > /dev/null 2>&1
docker volume rm l12_stale_vol > /dev/null 2>&1
docker volume create l12_stale_vol > /dev/null
docker run -d --name vm-stale-test --network vm-cluster-net -p 8459:8428 \
  -v l12_stale_vol:/victoria-metrics-data \
  victoriametrics/victoria-metrics:v1.151.0 \
  -storageDataPath=/victoria-metrics-data -httpListenAddr=:8428 \
  -retentionPeriod=30d -search.maxStalenessInterval=1h > /dev/null 2>&1
for i in $(seq 1 25); do
  R=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8459/health 2>/dev/null)
  [ "$R" = "200" ] && break
  sleep 1
done
curl -s -o /dev/null -w "  新实例 /health HTTP=%{http_code}\n" http://localhost:8459/health
echo "-- 往新实例写单点样本 --"
curl -s -o /dev/null -w "  写入 HTTP=%{http_code}\n" -X POST --data-binary 'l12_stale_single{job="l12"} 777' "http://localhost:8459/api/v1/import/prometheus"
sleep 3
echo "-- 查询（maxStalenessInterval=1h） --"
curl -s --data-urlencode 'query=l12_stale_single' "http://localhost:8459/api/v1/query" | head -c 250; echo

echo ""
echo "===== [6] 结论数据汇总 ====="
echo "  | 配置 | 单点样本可查性 |"
echo "  | 默认 staleness | 查不到 |"
echo "  | maxStalenessInterval=1h | $(curl -s --data-urlencode 'query=l12_stale_single' 'http://localhost:8459/api/v1/query' | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("查得到" if r else "查不到")') |"
echo "  | max_lookback=1h（查询时指定） | $(curl -s --data-urlencode 'query=l12_single' --data-urlencode 'max_lookback=1h' "$CLEAN/api/v1/query" | python3 -c 'import sys,json;r=json.load(sys.stdin)["data"]["result"];print("查得到" if r else "查不到")') |"
