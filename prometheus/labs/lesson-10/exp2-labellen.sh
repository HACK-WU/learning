#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-10
NET=l10net; PORT=19440

mem() { docker stats l10-prom --no-stream --format '{{.MemUsage}}' | awk '{print $1}' | sed 's/MiB//'; }
series() { curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['headStats']['numSeries'])"; }
labelpairs() { curl -s "http://localhost:$PORT/api/v1/status/tsdb" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['headStats']['numLabelPairs'])"; }

# 固定 5000 序列，只变标签值长度（短 vs 长）
run_len() {
  local vlen=$1 label=$2
  docker rm -f l10-prom >/dev/null 2>&1
  docker rm -f l10-app >/dev/null 2>&1
  docker run -d --name l10-app --network $NET \
    -e N_USERS=5000 -e VAL_LEN=$vlen l10-app >/dev/null 2>&1
  sleep 2
  docker run -d -p $PORT:9090 \
    -v $D/prometheus-base.yml:/etc/prometheus/prometheus.yml:ro \
    --name tmp-prom prom/prometheus:v3.14.0 \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus --web.enable-lifecycle --web.enable-admin-api >/dev/null 2>&1
  docker rename tmp-prom l10-prom >/dev/null 2>&1
  docker network connect $NET l10-prom >/dev/null 2>&1
  for i in $(seq 1 30); do curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && break; sleep 1; done
  sleep 25
  local m=$(mem)
  echo "$label|$(series)|$m|$(labelpairs)"
}

echo "############ 实验 2：标签值长度对内存的影响（固定 5000 序列）############"
echo "（固定序列数，只改标签值长度 —— 分离出「标签长度」这一个因子）"
echo ""
printf "%-30s %8s %10s %10s\n" "场景" "序列数" "内存MiB" "labelPairs"
echo "--------------------------------------------------------------------"
run_len 8 "短值 u000001 (8字符)"
run_len 64 "长值 64字符"
run_len 256 "超长值 256字符"
echo ""
echo "注：序列数固定 5000，差异应主要来自标签字符串本身"
