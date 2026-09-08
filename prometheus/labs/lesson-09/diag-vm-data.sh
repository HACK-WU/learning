#!/usr/bin/env bash
set -uo pipefail
NET=l9net
echo "=== 1. l9-prom-wr 是否在跑、有无报错 ==="
docker inspect -f '{{.State.Status}}' l9-prom-wr
docker logs l9-prom-wr 2>&1 | grep -iE 'error|level=error' | head -5

echo
echo "=== 2. l9-prom-wr 自己有没有抓到数据 ==="
docker run --rm --network $NET curlimages/curl:latest -s -G \
  --data-urlencode 'query=count(app_requests_total)' \
  http://l9-prom-wr:9090/api/v1/query 2>/dev/null | head -c 200
echo

echo
echo "=== 3. VM 写入统计 ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-vm-single:8428/metrics 2>/dev/null \
  | grep -E 'vm_rows_inserted_total|vm_remote_write' | head -8

echo
echo "=== 4. VM 里所有 __name__ ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-vm-single:8428/api/v1/label/__name__/values 2>/dev/null | head -c 400
echo

echo
echo "=== 5. prom-wr 的 remote write 队列状态 ==="
docker run --rm --network $NET curlimages/curl:latest -s \
  http://l9-prom-wr:9090/metrics 2>/dev/null \
  | grep -E 'prometheus_remote_storage_.*(sent|failed|pending)' | head -8
