#!/usr/bin/env bash
echo "=== VM 健康检查 ==="
docker exec l7-vm wget -qO- 'http://localhost:8428/health' 2>&1
echo

echo "=== VM 里有哪些 l7_ 开头的指标 ==="
docker exec l7-vm sh -c 'wget -qO- "http://localhost:8428/api/v1/label/__name__/values" 2>/dev/null' | head -c 1500
echo

echo "=== 直接查 count(l7_card_balance) ==="
docker exec l7-vm sh -c 'wget -qO- "http://localhost:8428/api/v1/query?query=count%28l7_card_balance%29" 2>/dev/null'
echo

echo "=== l7-prom-rr 日志尾部（remote write / read 是否报错） ==="
docker logs --tail 20 l7-prom-rr 2>&1 | grep -iE "remote|error|warn" | head -n 15

echo
echo "=== l7-prom-rr 的 remote write 指标 ==="
docker exec l7-prom-rr wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote_storage_samples_(in_total|total|pending)" | head -n 5
