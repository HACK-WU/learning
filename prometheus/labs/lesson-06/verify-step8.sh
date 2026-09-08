#!/usr/bin/env bash
# 复验步骤 8 修正后的命令（重点：.%2B 编码）
cd /mnt/d/projects/learning/prometheus/labs/lesson-06 || exit 1

echo "== 8.1 等值 vs 无界正则（不含 +，可直接 POST）=="
for Q in 'l6_card_metric{idx="000123"}' 'l6_card_metric{idx=~".*000123"}'; do
  echo "--- $Q ---"
  for i in 1 2 3 4 5; do
    /usr/bin/time -f "  %e" docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query" --post-data "query=$Q" > /dev/null
  done 2>&1
done

echo
echo "== 8.2 命中全库（用 .%2B，验证讲义修正是否有效）=="
for Q in 'l6_card_metric{idx="000123"}' '{__name__=~".%2B"}'; do
  echo "--- $Q ---"
  docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
    --post-data "query=$Q" \
    | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print('  命中序列数:',len(d))"
  for i in 1 2 3; do
    /usr/bin/time -f "  耗时: %e 秒" docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query" --post-data "query=$Q" > /dev/null
  done 2>&1
done

echo
echo "== 8.3 反向验证：讲义警告的坑是否真实存在（用 .+ 应命中 0）=="
docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
  --post-data 'query={__name__=~".+"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print('  .+  命中:',len(d))"
docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
  --post-data 'query={__name__=~".%2B"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print('  .%2B 命中:',len(d))"
