#!/bin/bash
# 最后一搏：用 range query + 超密集 step 制造确定性的秒级查询
# range query 的耗时 ∝ (时间跨度 ÷ step) × 序列数
set -u
END=$(date +%s)
START=$((END - 86400*7))   # 7 天

echo "=============================================="
echo " G0 构造 range query，逐步加大压力"
echo "=============================================="
SLOW='sum(l10_big_value) by (idx)'
for STEP in 60 10 1; do
  echo "  step=${STEP}s, 跨度=7天 (点数=$(( 86400*7 / STEP )))"
  T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 180 -G \
    -u backend:backend-pass-123 \
    --data-urlencode "query=$SLOW" \
    --data-urlencode "start=$START" --data-urlencode "end=$END" \
    --data-urlencode "step=$STEP" \
    'http://localhost:8427/api/v1/query_range')
  echo "     耗时: ${T}s"
done

echo
echo "=============================================="
echo " G1 若 range 还不够慢，直接造 10 万条序列的重查询"
echo "=============================================="
echo "  先写入一批高基数数据（l10_heavy）"
python3 - <<'PY'
import time
ts = (int(time.time()) - 120) * 1000000000
lines = ["l10_heavy,idx=%d,shard=%d,host=h%d value=%d %d"
         % (i, i%64, i%32, i, ts) for i in range(100000)]
open("/tmp/l10_heavy.influx","w").write("\n".join(lines)+"\n")
print("  准备 l10_heavy: 100000 条序列")
PY
S_T=$(date +%s)
curl -s -X POST --max-time 300 --data-binary @/tmp/l10_heavy.influx \
  'http://localhost:8480/insert/400/influx/write' -o /dev/null -w '  写入 HTTP %{http_code}\n'
E_T=$(date +%s)
echo "  写入耗时: $((E_T-S_T))s"
sleep 15

echo
echo "  -- 用 l10_heavy 做 range query --"
HEAVY='sum(rate(l10_heavy_value[5m])) by (shard)'
for STEP in 60 10; do
  T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 180 -G \
    --data-urlencode "query=$HEAVY" \
    --data-urlencode "start=$START" --data-urlencode "end=$END" \
    --data-urlencode "step=$STEP" \
    'http://localhost:8481/select/400/prometheus/api/v1/query_range')
  echo "     step=${STEP}s 耗时: ${T}s"
done

echo
echo "=============================================="
echo " G2 确定慢查询后，挂到 vmauth 后面测限流"
echo "=============================================="
cat > /tmp/vmauth-final.yml <<'YML'
users:
  - username: "backend"
    password: "backend-pass-123"
    url_map:
      - src_paths: ["/api/v1/query", "/api/v1/query_range"]
        url_prefix: ["http://vmsel-slow:8481/select/400/prometheus"]
  - username: "frontend"
    password: "frontend-pass-456"
    url_map:
      - src_paths: ["/api/v1/query", "/api/v1/query_range"]
        url_prefix: ["http://vmselect-learn:8481/select/200/prometheus"]
YML
docker rm -f vmauth-t >/dev/null 2>&1
docker run -d --name vmauth-t --network vm-cluster-net -p 8421:8427 \
  -v /tmp/vmauth-final.yml:/etc/vmauth/config.yml:ro \
  victoriametrics/vmauth:v1.151.0 \
  -auth.config=/etc/vmauth/config.yml \
  -maxConcurrentPerUserRequests=2 -maxQueueDuration=200ms \
  -httpListenAddr=:8427 >/dev/null 2>&1
for i in $(seq 1 30); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 'http://localhost:8421/health' 2>/dev/null)
  if [ "$c" = "200" ]; then echo "  vmauth-t 就绪 (8421)"; break; fi
  sleep 2
done

echo
echo "  -- 先验证 backend 走的是慢后端 --"
T=$(curl -s -o /dev/null -w '%{time_total}' --max-time 180 -G \
  -u backend:backend-pass-123 \
  --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
  --data-urlencode "end=$END" --data-urlencode "step=10" \
  'http://localhost:8421/api/v1/query_range')
echo "     backend 经 vmauth 单次耗时: ${T}s"

echo
echo "  -- 并发 40 个重查询 --"
TMP=$(mktemp)
for i in $(seq 1 40); do
  ( curl -s -o /dev/null -w '%{http_code}\n' --max-time 180 -G \
    -u backend:backend-pass-123 \
    --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
    --data-urlencode "end=$END" --data-urlencode "step=10" \
    'http://localhost:8421/api/v1/query_range' >> "$TMP" ) &
done
wait
echo "  -- 返回码分布 --"
sort "$TMP" | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP"

echo
echo "  -- 限流指标 --"
curl -s --max-time 15 'http://localhost:8421/metrics' 2>/dev/null \
  | grep -E 'limit_reached' | head -4

echo
echo "=============================================="
echo " G3 按用户隔离（最终验证）"
echo "=============================================="
TMP2=$(mktemp)
for i in $(seq 1 30); do
  ( curl -s -o /dev/null -w 'B%{http_code}\n' --max-time 180 -G \
    -u backend:backend-pass-123 \
    --data-urlencode "query=$HEAVY" --data-urlencode "start=$START" \
    --data-urlencode "end=$END" --data-urlencode "step=10" \
    'http://localhost:8421/api/v1/query_range' >> "$TMP2" ) &
done
for i in $(seq 1 8); do
  ( curl -s -o /dev/null -w 'F%{http_code}\n' --max-time 60 \
    -u frontend:frontend-pass-456 --data-urlencode "query=up" \
    'http://localhost:8421/api/v1/query' >> "$TMP2" ) &
done
wait
echo "  backend  (重查询, 慢后端, 限流=2):"
grep '^B' "$TMP2" | sed 's/^B//' | sort | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
echo "  frontend (轻查询, 快后端, 限流=2):"
grep '^F' "$TMP2" | sed 's/^F//' | sort | uniq -c | while read n c; do echo "      HTTP $c : $n 次"; done
rm -f "$TMP2"
