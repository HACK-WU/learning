#!/bin/bash
# 终测：制造真正耗时的查询来触发 vmauth 限流
# 前面失败的根本原因：查询 0.008s，并发不重叠
# 方案：用 subqueries + 超大范围 + 高基数聚合，制造秒级查询
set -u

echo "=============================================="
echo " S0 构造慢查询并测量单发耗时"
echo "=============================================="
# 用嵌套子查询 + quantile 强制 VM 扫描大量数据
SLOW='quantile_over_time(0.99, (sum(l10_big_value) by (idx, shard))[24h:10s])'
echo "  查询: $SLOW"
for i in 1 2 3; do
  T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 120 \
    -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
    'http://localhost:8427/api/v1/query')
  echo "    第 $i 次单发耗时: ${T}s"
done

echo
echo "=============================================="
echo " S1 若还是太快，用 -search.maxQueryDuration 制造人为延迟"
echo "=============================================="
echo "  或者改用【并发写入】而非查询来压测"
echo
echo "  方案：用 sleep 卡住后端不现实，改用 vmselect 的 -search.maxConcurrentRequests=1"
echo "  让后端本身变慢 → vmauth 的并发自然会堆积"

docker rm -f vmsel-slow >/dev/null 2>&1
docker run -d --name vmsel-slow --network vm-cluster-net -p 8423:8481 \
  victoriametrics/vmselect:v1.151.0-cluster \
  -storageNode=vmstorage-learn:8401 -storageNode=vmstorage-learn2:8401 \
  -dedup.minScrapeInterval=30s \
  -search.maxConcurrentRequests=1 \
  -httpListenAddr=:8481 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8423/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmselect(限并发=1) 就绪 (8423)"; break; fi
  sleep 2
done

echo
echo "  -- 先确认这个 vmselect 会排队 --"
TMP=$(mktemp)
for i in $(seq 1 20); do
  ( curl -s -o /dev/null -w '%{time_total}\n' --max-time 120 \
    --data-urlencode "query=$SLOW" \
    'http://localhost:8423/select/100/prometheus/api/v1/query' >> "$TMP" ) &
done
wait
echo "     并发 20 个查询的耗时分布:"
sort -n "$TMP" | awk '{a[NR]=$1} END {
  printf "       最快 %.3fs  中位 %.3fs  最慢 %.3fs\n", a[1], a[int(NR/2)], a[NR]}'
rm -f "$TMP"
echo "     （若最慢远大于最快，说明后端确实在排队）"

echo
echo "=============================================="
echo " S2 把这个慢后端挂到 vmauth 后面，测限流"
echo "=============================================="
cat > /tmp/vmauth-slow.yml <<'YML'
users:
  - username: "backend"
    password: "backend-pass-123"
    url_map:
      - src_paths: ["/api/v1/query", "/api/v1/query_range"]
        url_prefix: ["http://vmsel-slow:8481/select/100/prometheus"]
  - username: "frontend"
    password: "frontend-pass-456"
    url_map:
      - src_paths: ["/api/v1/query", "/api/v1/query_range"]
        url_prefix: ["http://vmselect-learn:8481/select/200/prometheus"]
YML

docker rm -f vmauth-slowtest >/dev/null 2>&1
docker run -d --name vmauth-slowtest \
  --network vm-cluster-net -p 8422:8427 \
  -v /tmp/vmauth-slow.yml:/etc/vmauth/config.yml:ro \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -maxConcurrentPerUserRequests=2 \
  -maxQueueDuration=200ms \
  -httpListenAddr=:8427 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8422/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth(慢后端) 就绪 (8422)"; break; fi
  sleep 2
done

echo
echo "  -- 并发 40 个查询打到慢后端 --"
TMP2=$(mktemp)
for i in $(seq 1 40); do
  ( curl -s -o /dev/null -w '%{http_code}\n' --max-time 120 \
    -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
    'http://localhost:8422/api/v1/query' >> "$TMP2" ) &
done
wait
echo "  -- 返回码分布 --"
sort "$TMP2" | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP2"

echo
echo "  -- 限流指标 --"
curl -s --max-time 15 'http://localhost:8422/metrics' 2>/dev/null \
  | grep -E 'limit_reached|user_concurrent' | head -6

echo
echo "=============================================="
echo " S3 按用户隔离验证（用慢后端场景）"
echo "=============================================="
TMP3=$(mktemp)
for i in $(seq 1 30); do
  ( curl -s -o /dev/null -w 'B%{http_code}\n' --max-time 120 \
    -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
    'http://localhost:8422/api/v1/query' >> "$TMP3" ) &
done
for i in $(seq 1 8); do
  ( curl -s -o /dev/null -w 'F%{http_code}\n' --max-time 120 \
    -u frontend:frontend-pass-456 --data-urlencode "query=up" \
    'http://localhost:8422/api/v1/query' >> "$TMP3" ) &
done
wait
echo "  backend  (走慢后端, 限流=2):"
grep '^B' "$TMP3" | sed 's/^B//' | sort | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
echo "  frontend (走快后端, 限流=2):"
grep '^F' "$TMP3" | sed 's/^F//' | sort | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP3"
echo
echo "  → 若 backend 有 429 而 frontend 全 200，"
echo "    证明【限流是按用户隔离的，一个租户打满不影响其他租户】"
