#!/bin/bash
# 补测：用真正的慢查询触发 vmauth 限流 429
# 上次失败原因：查询太快（毫秒级），20 个并发没有堆积
# 这次用【超大范围 + 高基数】查询制造秒级耗时
set -u
echo "=============================================="
echo " L0 先确认慢查询有多慢"
echo "=============================================="
SLOW='sum(rate(l10_big_value[24h])) by (idx)'
echo "  慢查询: $SLOW"
T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 60 \
  -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
  'http://localhost:8426/api/v1/query')
echo "  单发耗时: ${T}s"

echo
echo "=============================================="
echo " L1 并发 30 个慢查询（限流上限=2, 队列=1s）"
echo "=============================================="
echo "  预期：超过 2 个并发且在 1 秒内排不上队的请求 → 429"
echo
TMP=$(mktemp)
for i in $(seq 1 30); do
  ( curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 \
      -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
      'http://localhost:8426/api/v1/query' >> "$TMP" ) &
done
wait
echo "  -- 返回码分布 --"
sort "$TMP" | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP"

echo
echo "  -- 限流指标 --"
curl -s --max-time 15 'http://localhost:8426/metrics' 2>/dev/null \
  | grep -E 'vmauth_user_concurrent_requests_(capacity|current)|limit_reached' | head -6

echo
echo "=============================================="
echo " L2 对照：不设限流的 vmauth(8427) 同样并发"
echo "=============================================="
TMP2=$(mktemp)
for i in $(seq 1 30); do
  ( curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 \
      -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
      'http://localhost:8427/api/v1/query' >> "$TMP2" ) &
done
wait
echo "  -- 返回码分布 --"
sort "$TMP2" | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP2"

echo
echo "=============================================="
echo " L3 更激进：并发 60 + 更长的队列等待"
echo "=============================================="
echo "  重启一个限流更严的实例: 并发=1, 队列=100ms"
docker rm -f vmauth-strict >/dev/null 2>&1
docker run -d --name vmauth-strict \
  --network vm-cluster-net -p 8424:8427 \
  -v /mnt/d/projects/learning/victoriametrics/playground/vmauth-config.yml:/etc/vmauth/config.yml:ro \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -maxConcurrentPerUserRequests=1 \
  -maxQueueDuration=100ms \
  -httpListenAddr=:8427 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8424/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth(严格限流) 就绪 (8424)"; break; fi
  sleep 2
done

TMP3=$(mktemp)
for i in $(seq 1 60); do
  ( curl -s -o /dev/null -w '%{http_code}\n' --max-time 60 \
      -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
      'http://localhost:8424/api/v1/query' >> "$TMP3" ) &
done
wait
echo "  -- 返回码分布 --"
sort "$TMP3" | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP3"

echo
echo "  -- 指标 --"
curl -s --max-time 15 'http://localhost:8424/metrics' 2>/dev/null \
  | grep -E 'limit_reached|vmauth_user_concurrent_requests_capacity' | head -4

echo
echo "=============================================="
echo " L4 验证限流是【按用户】隔离的"
echo "=============================================="
echo "  backend 打满的同时，frontend 应该不受影响"
TMP4=$(mktemp)
for i in $(seq 1 20); do
  ( curl -s -o /dev/null -w 'F%{http_code}\n' --max-time 60 \
      -u backend:backend-pass-123 --data-urlencode "query=$SLOW" \
      'http://localhost:8424/api/v1/query' >> "$TMP4" ) &
done
for i in $(seq 1 5); do
  ( curl -s -o /dev/null -w 'G%{http_code}\n' --max-time 60 \
      -u frontend:frontend-pass-456 --data-urlencode "query=up" \
      'http://localhost:8424/api/v1/query' >> "$TMP4" ) &
done
wait
echo "  -- backend(F) vs frontend(G) --"
grep '^F' "$TMP4" | sed 's/^F/      backend  /' | sort | uniq -c | awk '{print $2" "$3" : "$1" 次"}'
grep '^G' "$TMP4" | sed 's/^G/      frontend /' | sort | uniq -c | awk '{print $2" "$3" : "$1" 次"}'
rm -f "$TMP4"
echo
echo "  → 若 frontend 全 200 而 backend 有 429，说明限流是【按用户隔离】的"
