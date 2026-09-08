set -e
NET=lesson01-net

for pair in "l1-demo-app:demo-app" "l1-node:node-exporter" "l1-pushgateway:pushgateway"; do
  c="${pair%%:*}"
  alias_name="${pair##*:}"
  docker network disconnect "$NET" "$c" >/dev/null 2>&1 || true
  docker network connect --alias "$alias_name" "$NET" "$c" >/dev/null 2>&1 || true
  echo "$c -> alias $alias_name"
done

docker network disconnect "$NET" l1-prometheus >/dev/null 2>&1 || true
docker network connect "$NET" l1-prometheus >/dev/null 2>&1 || true

sleep 2
echo "--- resolve from prometheus ---"
docker exec l1-prometheus getent hosts demo-app || echo "FAIL demo-app"
docker exec l1-prometheus getent hosts node-exporter || echo "FAIL node-exporter"
docker exec l1-prometheus getent hosts pushgateway || echo "FAIL pushgateway"
