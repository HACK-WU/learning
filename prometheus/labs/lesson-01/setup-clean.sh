set -x

for c in l1-demo-app l1-node l1-pushgateway l1-prometheus l1-echo l1-prom-proto; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

docker network rm lesson01-net >/dev/null 2>&1 || true

echo "=== 端口占用检查 ==="
ss -ltn 2>/dev/null | grep -E ':(8080|8081|9090|9091|9095)' || echo "(8080/8081/9090/9091/9095 均空闲或有输出如上)"
