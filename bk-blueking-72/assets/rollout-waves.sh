#!/usr/bin/env bash
# 分批启动 blueking pods，避免 190 个 Pod 同时冷启动打爆内存
# 用法: bash rollout-waves.sh
set -u

NS=blueking
WAVE1="bk-mysql8 bk-redis bk-mongodb bk-etcd bk-zookeeper bk-rabbitmq"
WAVE2="bk-elastic bk-kafka"
WAVE3="bk-cmdb bk-iam bk-user bk-apigateway bk-gse"
WAVE4="bk-paas bk-ssm bk-auth bk-login bk-console"
WAVE5="bk-repo bk-applog bk-nodeman bk-monitor"

wait_ready() {
  local label="$1"; shift
  local timeout="$1"; shift
  echo "  [$label] waiting up to ${timeout}s ..."
  for dep in "$@"; do
    local has
    has=$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk -v d="$dep" '$1 ~ "^"d {print $1}')
    [ -z "$has" ] && continue
    for d in $has; do
      kubectl rollout status deploy/"$d" -n $NS --timeout="${timeout}s" >/dev/null 2>&1 \
        && echo "    OK   $d" || echo "    SLOW $d (continuing)"
    done
  done
}

mem() {
  free -m | awk 'NR==2{printf "%dMi used / avail %dMi", $3, $7}'
}

echo "=== ROLLOUT WAVES (memory-safe) ==="
echo "  start: $(mem)"
echo ""

echo "--- WAVE 1: storage ---"; wait_ready W1 180 $WAVE1; echo "  mem: $(mem)"
echo ""
echo "--- WAVE 2: search/mq ---"; wait_ready W2 240 $WAVE2; echo "  mem: $(mem)"
echo ""
echo "--- WAVE 3: core platform ---"; wait_ready W3 300 $WAVE3; echo "  mem: $(mem)"
echo ""
echo "--- WAVE 4: access/console ---"; wait_ready W4 240 $WAVE4; echo "  mem: $(mem)"
echo ""
echo "--- WAVE 5: heavy apps ---"; wait_ready W5 300 $WAVE5; echo "  mem: $(mem)"
echo ""

echo "=== FINAL ==="
echo "  mem: $(mem)"
echo "  pods: $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"
echo "  not-ready: $(kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed" && $3!="Succeeded"' | wc -l)"
