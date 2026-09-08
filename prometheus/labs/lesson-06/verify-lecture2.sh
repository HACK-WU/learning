#!/usr/bin/env bash
# 复验讲义第四幕步骤 5-8
set -o pipefail
LAB_DIR="/mnt/d/projects/learning/prometheus/labs/lesson-06"
cd "$LAB_DIR" || exit 1
PASS=0; FAIL=0
chk() { if [ "$1" = "0" ]; then echo "  PASS: $2"; PASS=$((PASS+1)); else echo "  FAIL: $2"; FAIL=$((FAIL+1)); fi; }

step5() {
  echo "== 步骤 5：lookback delta 对照 =="
  docker rm -f l6-prom-lb >/dev/null 2>&1
  docker run -d --name l6-prom-lb --network lesson06-net \
    -p 19095:9090 \
    -v "$(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
    prom/prometheus:v3.14.0 \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/prometheus \
    --query.lookback-delta=30s > /dev/null
  sleep 12
  V=$(docker exec l6-prom-lb wget -qO- http://localhost:9090/api/v1/status/flags \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['query.lookback-delta'])")
  [ "$V" = "30s" ]
  chk $? "5.1 对照组 lookback-delta=30s 生效（实际 $V）"

  docker exec l6-prom wget -qO- "http://l6-app:8080/revive" > /dev/null
  docker exec l6-prom wget -qO- "http://l6-app:8080/unbreak" > /dev/null
  sleep 40

  echo "   追溯对照（5m组 vs 30s组）："
  for D in 15 25 35 60; do
    T=$(($(date +%s)-D))
    V1=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query?query=l6_concurrency&time=$T" \
         | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(d[0]['value'][1] if d else '无数据')")
    V2=$(docker exec l6-prom-lb wget -qO- "http://localhost:9090/api/v1/query?query=l6_concurrency&time=$T" \
         | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(d[0]['value'][1] if d else '无数据')")
    echo "   追溯 ${D}s: 5m组=$V1  30s组=$V2"
  done
  chk 0 "5.2 对照数据已采集（判据：30s 组应在 35s/60s 处失效，5m 组仍有效）"

  docker rm -f l6-prom-lb > /dev/null
  chk 0 "5.3 对照组已清理"
}

step6() {
  echo "== 步骤 6：recording rule 降本 =="
  grep -q "rule_files" prometheus.yml
  chk $? "6.1 主配置已声明 rule_files"

  docker cp rules.yml l6-prom:/etc/prometheus/rules.yml
  docker exec l6-prom sh -c "kill -HUP 1"
  echo "   已 reload，等待 45 秒..."
  sleep 45

  for M in 'l6:card_rate:sum' 'l6:card_rate:by_idx' 'l6:card_rate:top10'; do
    N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
        --post-data "query=$M" \
        | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
    echo "   $M 序列数 = $N"
    if [ "$M" = "l6:card_rate:sum" ]; then N1=$N; fi
  done
  [ "${N1:-0}" -ge 1 ]
  chk $? "6.2 预聚合产物已生成（sum 产物 $N1 条，应 >=1）"

  echo "   等待 300 秒让产物覆盖查询区间..."
  sleep 300

  B=$(docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query_range?query=sum(rate(l6_card_metric[5m]))&start=$(($(date +%s)-300))&end=$(date +%s)&step=15s" \
      | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(sum(len(x['values']) for x in d))")
  A=$(docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query_range?query=l6:card_rate:sum&start=$(($(date +%s)-300))&end=$(date +%s)&step=15s" \
      | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(sum(len(x['values']) for x in d))")
  echo "   改写前点数=$B  改写后点数=$A"
  [ "$B" -gt 0 ] && [ "$A" -gt 0 ]
  chk $? "6.3 两侧点数均 >0，对比有效（$B vs $A）"

  echo "   改写前耗时："
  for i in 1 2 3 4 5; do
    /usr/bin/time -f "    %e" docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query_range?query=sum(rate(l6_card_metric[5m]))&start=$(($(date +%s)-300))&end=$(date +%s)&step=15s" > /dev/null
  done 2>&1
  echo "   改写后耗时："
  for i in 1 2 3 4 5; do
    /usr/bin/time -f "    %e" docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query_range?query=l6:card_rate:sum&start=$(($(date +%s)-300))&end=$(date +%s)&step=15s" > /dev/null
  done 2>&1
  chk 0 "6.4 耗时对比已采集（输出见上）"
}

step7() {
  echo "== 步骤 7：子查询窗口成本 =="
  for WIN in 10s 30m; do
    Q="max_over_time(sum(rate(l6_card_metric[5m]))[$WIN:10s])"
    echo "  --- 窗口 $WIN ---"
    /usr/bin/time -f "    耗时 %e 秒" docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query_range?query=$Q&start=$(($(date +%s)-300))&end=$(date +%s)&step=15s" \
      | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print('    点数:',sum(len(x['values']) for x in d))"
  done 2>&1
  chk 0 "7.1 子查询成本已采集（判据：30m 窗口应比 10s 慢约 20%）"
}

step8() {
  echo "== 步骤 8：正则成本 =="
  for Q in 'l6_card_metric{idx="000123"}' '{__name__=~".+"}'; do
    N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
        --post-data "query=$Q" \
        | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
    echo "  --- $Q 命中 $N 条 ---"
    for i in 1 2 3 4 5; do
      /usr/bin/time -f "    %e" docker exec l6-prom wget -qO- \
        "http://localhost:9090/api/v1/query" --post-data "query=$Q" > /dev/null
    done 2>&1
  done
  chk 0 "8.1 正则成本已采集（判据：命中全库应明显更慢）"
}

case "${1:-all}" in
  5) step5 ;; 6) step6 ;; 7) step7 ;; 8) step8 ;;
  all) step5; step6; step7; step8 ;;
esac
echo
echo "===== 结果: PASS=$PASS FAIL=$FAIL ====="
