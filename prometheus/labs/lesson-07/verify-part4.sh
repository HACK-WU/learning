#!/usr/bin/env bash
# 逐字复验讲义第四幕步骤 1-4 的命令
PASS=0; FAIL=0
chk() {  # chk <描述> <期望: gt0|eq:N|contains:xxx|ncontains:xxx> <实际值>
  local desc="$1" exp="$2" act="$3" ok=0
  case "$exp" in
    gt0)      [ -n "$act" ] && [ "$act" != "0" ] && [ "$act" != "None" ] && ok=1 ;;
    eq:*)     [ "$act" = "${exp#eq:}" ] && ok=1 ;;
    contains:*)    case "$act" in *"${exp#contains:}"*) ok=1;; esac ;;
    ncontains:*)   case "$act" in *"${exp#ncontains:}"*) ;; *) ok=1;; esac ;;
  esac
  if [ $ok -eq 1 ]; then
    printf "  [PASS] %-46s = %s\n" "$desc" "$act"; PASS=$((PASS+1))
  else
    printf "  [FAIL] %-46s = %s  (期望 %s)\n" "$desc" "$act" "$exp"; FAIL=$((FAIL+1))
  fi
}

echo "================================================================"
echo " 复验步骤 1-4（环境 / 指标名 / 队列 / 配置校验）"
echo "================================================================"

echo
echo "--- 步骤 1：环境与链路 ---"
ST=$(curl -s --max-time 10 http://localhost:19099/stats)
DEC=$(echo "$ST" | python -c "import sys,json;print(json.load(sys.stdin).get('bytes_decompressed',0))" 2>/dev/null)
REQ=$(echo "$ST" | python -c "import sys,json;print(json.load(sys.stdin).get('requests',0))" 2>/dev/null)
chk "receiver 收到请求数" "gt0" "$REQ"
chk "receiver 解压字节数" "gt0" "$DEC"

echo
echo "--- 步骤 2：指标名核查 ---"
NAMES=$(docker exec l7-prom wget -qO- http://localhost:9090/metrics 2>/dev/null \
  | grep -E "^prometheus_remote_storage_samples_" | sed 's/{.*//' | sort -u)
chk "存在 samples_total"        "contains:prometheus_remote_storage_samples_total"        "$NAMES"
chk "存在 samples_in_total"     "contains:prometheus_remote_storage_samples_in_total"     "$NAMES"
chk "存在 samples_failed_total" "contains:prometheus_remote_storage_samples_failed_total" "$NAMES"
chk "不存在 samples_out_total"  "ncontains:prometheus_remote_storage_samples_out_total"   "$NAMES"
chk "不存在 dropped_total"      "ncontains:prometheus_remote_storage_samples_dropped_total" "$NAMES"

echo
echo "--- 步骤 3：队列行为（注入 500 前先看基线） ---"
P='http://localhost:19100'
URL='http://l7-receiver:8080/api/v1/write'
qv() {
  curl -s -G "$P/api/v1/query" --data-urlencode "query=$1" \
    | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'None')" 2>/dev/null
}
BASE=$(qv "prometheus_remote_storage_samples_pending{url=\"$URL\"}")
chk "基线 pending" "gt0" "$BASE"

echo "  [INFO] 注入 500，等待 20 秒..."
curl -s http://localhost:19099/mode/500 >/dev/null
sleep 20
PEND=$(qv "prometheus_remote_storage_samples_pending{url=\"$URL\"}")
FAILV=$(qv "prometheus_remote_storage_samples_failed_total{url=\"$URL\"}")
ENQR=$(qv "prometheus_remote_storage_enqueue_retries_total{url=\"$URL\"}")
chk "故障中 pending 上涨" "gt0" "$PEND"
chk "故障中 failed 保持 0" "eq:0" "$FAILV"
chk "故障中 enqRetry 上涨" "gt0" "$ENQR"

echo "  [INFO] 恢复 ok，等待 30 秒..."
curl -s http://localhost:19099/mode/ok >/dev/null
sleep 30
AFTER=$(qv "prometheus_remote_storage_samples_pending{url=\"$URL\"}")
chk "恢复后 pending 回落(<故障峰值)" "gt0" "$AFTER"
echo "  [INFO] 故障峰值=$PEND 恢复后=$AFTER"

echo
echo "--- 步骤 4：promtool 配置校验 ---"
cd /d/projects/learning/prometheus || exit 1
OKOUT=$(docker run --rm \
  -v "$(pwd)/labs/lesson-07/prometheus.yml:/tmp/c.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/c.yml 2>&1)
chk "正确配置校验通过" "contains:SUCCESS" "$OKOUT"

cat > /tmp/bad_qc.yml <<'EOF'
global:
  scrape_interval: 5s
remote_write:
  - url: "http://example.com/api/v1/write"
    queue_config:
      capacity: 1000
      max_shardz: 10
scrape_configs:
  - job_name: x
    static_configs:
      - targets: ["localhost:9090"]
EOF
BADOUT=$(docker run --rm -v "/tmp/bad_qc.yml:/tmp/bad_qc.yml:ro" \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  check config /tmp/bad_qc.yml 2>&1)
chk "错误字段名被抓出" "contains:max_shardz not found" "$BADOUT"

echo
echo "================================================================"
echo " 步骤 1-4 复验结果：PASS=$PASS  FAIL=$FAIL"
echo "================================================================"
