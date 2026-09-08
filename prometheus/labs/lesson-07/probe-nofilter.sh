#!/usr/bin/env bash
set -u
L7="$(pwd)/labs/lesson-07"

echo "=== 校验配置 ==="
docker run --rm -v "$L7/prometheus-rr-nofilter.yml:/tmp/c.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/c.yml 2>&1 | tail -n 3

echo
echo "=== 启动对照实例：filter_external_labels=false ==="
docker rm -f l7-prom-nf >/dev/null 2>&1 || true
docker run -d --name l7-prom-nf --network l7net -p 19104:9090 \
  -v "$L7/prometheus-rr-nofilter.yml:/etc/prometheus/prometheus.yml:ro" \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15m \
  --web.enable-lifecycle >/dev/null
echo "l7-prom-nf up (http://localhost:19104)"

sleep 18

echo
echo "=== 三方对照：查同一条查询 l7_card_balance ==="
for name in l7-prom-ro l7-prom-nf l7-prom-rr; do
  case $name in
    l7-prom-ro) port=19103 ;;
    l7-prom-nf) port=19104 ;;
    l7-prom-rr) port=19102 ;;
  esac
  n=$(docker exec $name wget -qO- --timeout=10 \
      "http://localhost:9090/api/v1/query?query=l7_card_balance" 2>/dev/null \
      | grep -o '"result":\[' | wc -l)
  cnt=$(docker exec $name wget -qO- --timeout=10 \
      "http://localhost:9090/api/v1/query?query=count%28l7_card_balance%29" 2>/dev/null \
      | sed 's/.*"value":\[[0-9]*,"\([0-9]*\)".*/\1/')
  echo "  $name (port $port): count(l7_card_balance) = ${cnt:-ERR}"
done

echo
echo "=== 直接经宿主机端口对照 ==="
for port in 19102 19103 19104; do
  echo -n "  port $port: "
  curl -s --max-time 10 --data-urlencode 'query=count(l7_card_balance)' \
    "http://localhost:$port/api/v1/query" 2>/dev/null \
    | sed 's/.*"value":\[[0-9]*,"\([0-9]*\)".*/count=\1/' | head -c 60
  echo
done
