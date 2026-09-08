#!/usr/bin/env bash
# 诊断：为什么复验脚本里 {__name__=~".+"} 命中 0 条，单独跑却命中 40830 条？
cd /mnt/d/projects/learning/prometheus/labs/lesson-06 || exit 1

echo "== A. 用复验脚本里的写法（双引号 + \$Q） =="
Q='{__name__=~".+"}'
echo "Q=$Q"
N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
    --post-data "query=$Q" \
    | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
echo "命中: $N"

echo
echo "== B. 直接写死，不用变量 =="
N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
    --post-data 'query={__name__=~".+"}' \
    | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
echo "命中: $N"

echo
echo "== C. 看 A 的裸响应（前 200 字符） =="
docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
  --post-data "query=$Q" | head -c 200
echo

echo
echo "== D. 对比：讲义里写的 l6_card_metric{idx=\"000123\"} =="
Q2='l6_card_metric{idx="000123"}'
N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
    --post-data "query=$Q2" \
    | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
echo "命中: $N"
