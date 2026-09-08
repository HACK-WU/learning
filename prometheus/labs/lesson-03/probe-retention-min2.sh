set -x
for t in 1s 1m 5m 2h; do
  echo "--- retention.time=$t ---"
  timeout 12 docker run --rm --entrypoint /bin/sh prom/prometheus:v3.14.0 -c \
    "prometheus --storage.tsdb.path=/tmp/x --storage.tsdb.retention.time=$t \
     --config.file=/etc/prometheus/prometheus.yml 2>&1 | grep -iE 'retention updated' | head -2"
  echo "  exit=$?"
done
