set -x
for t in 1s 1m 5m 30m 2h; do
  echo "--- retention.time=$t ---"
  docker run --rm --entrypoint /bin/sh prom/prometheus:v3.14.0 -c \
    "prometheus --storage.tsdb.path=/tmp/x --storage.tsdb.retention.time=$t --config.file=/dev/null 2>&1 | grep -iE 'retention updated|level=ERROR' | head -2"
done
