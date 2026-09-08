#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet; PORT=19457
N=${N:-100000}

docker rm -f l11c-q >/dev/null 2>&1 || true
docker rm -f l11c-qapp >/dev/null 2>&1 || true
rm -rf $D/data-q; mkdir -p $D/data-q
docker run -d --name l11c-qapp --network $NET -e N_SERIES=$N -e VAL_LEN=12 -e LABELS=1 l11c-app >/dev/null
sleep 2
docker run -d --name l11c-q --network $NET -p $PORT:9090 \
  -v $D/prometheus-self.yml:/etc/prometheus/prometheus.yml:ro \
  -v $D/data-q:/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null
for i in $(seq 1 60); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
sleep 60

mem(){ docker exec l11c-q cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0; }

echo "=== 稳态基线 ==="
B=$(mem); echo "  $((B/1024/1024)) MiB"

echo ""
echo "=== 查询 1：count 全量（最轻） ==="
M1=0
for i in $(seq 1 3); do
  curl -s --data-urlencode 'query=count(l11_series)' "http://localhost:$PORT/api/v1/query" >/dev/null
  V=$(mem); [ "$V" -gt "$M1" ] && M1=$V
done
echo "  峰值 $((M1/1024/1024)) MiB  (Δ $(( (M1-B)/1024/1024 )) MiB)"

echo ""
echo "=== 查询 2：全量返回所有序列（最重） ==="
M2=0
for i in $(seq 1 5); do
  curl -s --data-urlencode 'query=l11_series' "http://localhost:$PORT/api/v1/query" >/dev/null
  V=$(mem); [ "$V" -gt "$M2" ] && M2=$V
done
echo "  峰值 $((M2/1024/1024)) MiB  (Δ $(( (M2-B)/1024/1024 )) MiB)"

echo ""
echo "=== 查询 3：全量 + 聚合 by 高基数字段 ==="
M3=0
for i in $(seq 1 5); do
  curl -s --data-urlencode 'query=sum by (idx) (l11_series)' "http://localhost:$PORT/api/v1/query" >/dev/null
  V=$(mem); [ "$V" -gt "$M3" ] && M3=$V
done
echo "  峰值 $((M3/1024/1024)) MiB  (Δ $(( (M3-B)/1024/1024 )) MiB)"

echo ""
echo "=== 查询 4：并发 5 个全量查询 ==="
M4=0
for i in $(seq 1 5); do curl -s --data-urlencode 'query=l11_series' "http://localhost:$PORT/api/v1/query" >/dev/null & done
for i in $(seq 1 20); do
  V=$(mem); [ "$V" -gt "$M4" ] && M4=$V
  sleep 0.5
done
wait
echo "  峰值 $((M4/1024/1024)) MiB  (Δ $(( (M4-B)/1024/1024 )) MiB)"

echo ""
echo "RESULT|$N|$((B/1024/1024))|$((M1/1024/1024))|$((M2/1024/1024))|$((M3/1024/1024))|$((M4/1024/1024))"
