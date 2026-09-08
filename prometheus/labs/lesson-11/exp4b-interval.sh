#!/usr/bin/env bash
# 抓取间隔实验（独占容器名 l11c-iv，避免与其他实验冲突）
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet; PORT=19458
OUT=$D/results-interval.txt
RUN=${RUN:-480}     # 每组运行秒数，默认 8 分钟
: > $OUT
echo "# interval|scrape_duration_s|samples_scraped|mem_MiB|disk_MiB|span_min" | tee -a $OUT

for IV in 5s 15s 60s; do
  echo "--- scrape_interval=$IV ---" >&2
  SEC=${IV%s}
  cat > $D/prom-iv.yml <<EOF
global:
  scrape_interval: $IV
  evaluation_interval: $IV
  scrape_timeout: ${SEC}s
scrape_configs:
  - job_name: "l11"
    static_configs:
      - targets: ["l11c-ivapp:8000"]
EOF
  docker rm -f l11c-iv l11c-ivapp >/dev/null 2>&1 || true
  rm -rf $D/data-iv; mkdir -p $D/data-iv
  docker run -d --name l11c-ivapp --network $NET -e N_SERIES=50000 -e VAL_LEN=12 -e LABELS=1 l11c-app >/dev/null
  sleep 2
  docker run -d --name l11c-iv --network $NET -p $PORT:9090 \
    -v $D/prom-iv.yml:/etc/prometheus/prometheus.yml:ro \
    -v $D/data-iv:/prometheus \
    prom/prometheus:v3.14.0 \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --storage.tsdb.retention.time=2h \
    --web.enable-lifecycle --web.enable-admin-api >/dev/null
  for i in $(seq 1 60); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
  sleep $RUN

  MEM=$(docker exec l11c-iv cat /sys/fs/cgroup/memory.current)
  DISK=$(docker exec l11c-iv du -sm /prometheus | awk '{print $1}')
  SD=$(curl -s --data-urlencode 'query=scrape_duration_seconds{job="l11"}' "http://localhost:$PORT/api/v1/query" \
    | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'NA')")
  SS=$(curl -s --data-urlencode 'query=scrape_samples_scraped{job="l11"}' "http://localhost:$PORT/api/v1/query" \
    | python3 -c "import sys,json;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'NA')")
  SPAN=$(curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
    | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['headStats'];print(f\"{(d['maxTime']-d['minTime'])/60000:.1f}\")")
  echo "$IV|$SD|$SS|$((MEM/1024/1024))|$DISK|$SPAN" | tee -a $OUT
done
echo "DONE"
