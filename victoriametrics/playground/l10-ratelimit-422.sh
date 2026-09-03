#!/bin/bash
# 查明 422 的原因
set -u
END=$(date +%s); START=$((END - 86400*7))
HEAVY='sum(rate(l10_heavy_value[5m])) by (shard)'

echo "=============================================="
echo " E1 看 422 的具体报错"
echo "=============================================="
echo "  -- 经 vmauth(8421) --"
curl -s -G --max-time 180 -u backend:backend-pass-123 \
  --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
  --data-urlencode "end=$END" --data-urlencode "step=60" \
  'http://localhost:8421/api/v1/query_range' 2>&1 | head -5

echo
echo "  -- 直连 vmsel-slow(8423) --"
curl -s -G --max-time 180 \
  --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
  --data-urlencode "end=$END" --data-urlencode "step=60" \
  'http://localhost:8423/select/400/prometheus/api/v1/query_range' 2>&1 | head -5

echo
echo "  -- 直连正常 vmselect(8481) --"
curl -s -G --max-time 180 \
  --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
  --data-urlencode "end=$END" --data-urlencode "step=60" \
  'http://localhost:8481/select/400/prometheus/api/v1/query_range' 2>&1 | head -3

echo
echo "=============================================="
echo " E2 vmsel-slow 的日志"
echo "=============================================="
docker logs vmsel-slow 2>&1 | tail -10

echo
echo "=============================================="
echo " E3 是不是 -search.maxQueryDuration 或 subquery 限制"
echo "=============================================="
echo "  vmsel-slow 参数:"
docker inspect vmsel-slow --format '  {{.Args}}'
echo
echo "  ⚠️ -search.maxConcurrentRequests=1 时，超出的请求会被"
echo "     直接拒绝（不是排队），可能是 422 的来源"
echo
echo "  -- 验证：把并发限制去掉，重建一个正常的慢后端 --"
docker rm -f vmsel-slow2 >/dev/null 2>&1
docker run -d --name vmsel-slow2 --network vm-cluster-net -p 8420:8481 \
  victoriametrics/vmselect:v1.151.0-cluster \
  -storageNode=vmstorage-learn:8401 -storageNode=vmstorage-learn2:8401 \
  -dedup.minScrapeInterval=30s \
  -httpListenAddr=:8481 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8420/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmsel-slow2 就绪 (8420)"; break; fi
  sleep 2
done

T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 180 -G \
  --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
  --data-urlencode "end=$END" --data-urlencode "step=60" \
  'http://localhost:8420/select/400/prometheus/api/v1/query_range')
echo "  vmsel-slow2 单次重查询耗时: ${T}s"

echo
echo "=============================================="
echo " E4 用 vmsel-slow2 重做限流测试"
echo "=============================================="
cat > /tmp/vmauth-e4.yml <<'YML'
users:
  - username: "backend"
    password: "backend-pass-123"
    url_map:
      - src_paths: ["/api/v1/query", "/api/v1/query_range"]
        url_prefix: ["http://vmsel-slow2:8481/select/400/prometheus"]
  - username: "frontend"
    password: "frontend-pass-456"
    url_map:
      - src_paths: ["/api/v1/query", "/api/v1/query_range"]
        url_prefix: ["http://vmselect-learn:8481/select/200/prometheus"]
YML
docker rm -f vmauth-e4 >/dev/null 2>&1
docker run -d --name vmauth-e4 --network vm-cluster-net -p 8419:8427 \
  -v /tmp/vmauth-e4.yml:/etc/vmauth/config.yml:ro \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -maxConcurrentPerUserRequests=2 -maxQueueDuration=200ms \
  -httpListenAddr=:8427 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8419/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth-e4 就绪 (8419)"; break; fi
  sleep 2
done

echo
echo "  -- 并发 40 个重查询（每个约 1.3s）--"
TMP=$(mktemp)
for i in $(seq 1 40); do
  ( curl -s -o /dev/null -w '%{http_code}\n' --max-time 180 -G \
    -u backend:backend-pass-123 \
    --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
    --data-urlencode "end=$END" --data-urlencode "step=60" \
    'http://localhost:8419/api/v1/query_range' >> "$TMP" ) &
done
wait
echo "  -- 返回码分布 --"
sort "$TMP" | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP"

echo
echo "  -- 限流指标 --"
curl -s --max-time 15 'http://localhost:8419/metrics' 2>/dev/null \
  | grep -E 'limit_reached' | head -4

echo
echo "=============================================="
echo " E5 按用户隔离（用能跑通的慢查询）"
echo "=============================================="
TMP2=$(mktemp)
for i in $(seq 1 30); do
  ( curl -s -o /dev/null -w 'B%{http_code}\n' --max-time 180 -G \
    -u backend:backend-pass-123 \
    --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
    --data-urlencode "end=$END" --data-urlencode "step=60" \
    'http://localhost:8419/api/v1/query_range' >> "$TMP2" ) &
done
for i in $(seq 1 8); do
  ( curl -s -o /dev/null -w 'F%{http_code}\n' --max-time 60 \
    -u frontend:frontend-pass-456 --data-urlencode "query=up" \
    'http://localhost:8419/api/v1/query' >> "$TMP2" ) &
done
wait
echo "  backend  (重查询 ~1.3s, 限流=2):"
grep '^B' "$TMP2" | sed 's/^B//' | sort | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
echo "  frontend (轻查询, 限流=2):"
grep '^F' "$TMP2" | sed 's/^F//' | sort | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP2"
