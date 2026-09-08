#!/usr/bin/env bash
# 逐字复验讲义第四幕的命令，验证读者照抄能否跑通
# 用法: bash verify-lecture.sh [步骤号]，不传则全部
set -o pipefail

LAB_DIR="/mnt/d/projects/learning/prometheus/labs/lesson-06"
cd "$LAB_DIR" || exit 1

PASS=0
FAIL=0

chk() {
  if [ "$1" = "0" ]; then
    echo "  PASS: $2"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $2"
    FAIL=$((FAIL+1))
  fi
}

step1() {
  echo "== 步骤 1：确认环境与基线 =="
  docker logs l6-prom 2>&1 | grep -q 'version=3.14.0'
  chk $? "1.1 Prometheus 版本为 3.14.0"

  N=$(docker exec l6-prom wget -qO- 'http://localhost:9090/api/v1/targets?state=active' \
      | python3 -c "
import sys,json
ts=json.load(sys.stdin)['data']['activeTargets']
print(sum(1 for t in ts if t.get('health')=='up'))
")
  [ "$N" -ge 2 ]
  chk $? "1.2 至少 2 个 target 处于 up（实际 $N）"

  N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
      --post-data 'query={__name__=~"l6_.*"}' \
      | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
  [ "$N" -ge 4 ]
  chk $? "1.3 业务指标已入库（实际 $N 条，应 >=4）"
}

step2() {
  echo "== 步骤 2：噪声基线 =="
  echo "  （记录 10 次耗时，供人工判读；判据：中位数约 130ms，波动 ±30ms）"
  for i in $(seq 1 10); do
    /usr/bin/time -f "  %e" docker exec l6-prom wget -qO- \
      "http://localhost:9090/api/v1/query" \
      --post-data 'query=l6_requests_total' > /dev/null
  done 2>&1
  chk 0 "2.1 噪声基线测量完成（输出见上）"
}

step3() {
  echo "== 步骤 3：成本 ≈ 序列数 × 点数 =="
  docker exec l6-prom wget -qO- "http://l6-app:8080/cardinality?n=20000" | grep -q '"series":20000'
  chk $? "3.1 生成 20000 条序列"
  sleep 10

  P1=$(docker exec l6-prom wget -qO- \
    "http://localhost:9090/api/v1/query_range?query=topk(20000,l6_card_metric)&start=$(($(date +%s)-300))&end=$(date +%s)&step=1s" \
    | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(sum(len(x['values']) for x in d))")
  P2=$(docker exec l6-prom wget -qO- \
    "http://localhost:9090/api/v1/query_range?query=topk(20000,l6_card_metric)&start=$(($(date +%s)-300))&end=$(date +%s)&step=300s" \
    | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(sum(len(x['values']) for x in d))")
  echo "    step=1s 点数=$P1 ; step=300s 点数=$P2"
  [ "$P1" -gt "$P2" ]
  chk $? "3.2 step 越小点数越多（$P1 > $P2）"

  S1=$(docker exec l6-prom wget -qO- \
    "http://localhost:9090/api/v1/query_range?query=sum(l6_card_metric)&start=$(($(date +%s)-300))&end=$(date +%s)&step=15s" \
    | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(len(d))")
  [ "$S1" -eq 1 ]
  chk $? "3.3 sum 聚合后序列数为 1（实际 $S1）"
}

step4() {
  echo "== 步骤 4：staleness marker =="
  docker exec l6-prom wget -qO- "http://l6-app:8080/revive" > /dev/null
  docker exec l6-prom wget -qO- "http://l6-app:8080/unbreak" > /dev/null
  sleep 8

  docker exec l6-prom wget -qO- "http://l6-app:8080/kill" > /dev/null
  sleep 6
  N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
      --post-data 'query=l6_concurrency' \
      | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
  [ "$N" -eq 0 ]
  chk $? "4.1 kill 后 6 秒序列消失（实际 $N 条，应为 0）"

  R=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
      --post-data 'query=sum(l6_concurrency) < 1' \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['result'])")
  [ "$R" = "[]" ]
  chk $? "4.2 空向量比较返回 [] 而非 true（实际 $R）"

  A=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
      --post-data 'query=absent(l6_concurrency)' \
      | python3 -c "import sys,json;d=json.load(sys.stdin)['data']['result'];print(d[0]['value'][1] if d else 'None')")
  [ "$A" = "1" ]
  chk $? "4.3 absent() 正确返回 1（实际 $A）"

  docker exec l6-prom wget -qO- "http://l6-app:8080/revive" > /dev/null
  sleep 8
  N=$(docker exec l6-prom wget -qO- "http://localhost:9090/api/v1/query" \
      --post-data 'query=l6_concurrency' \
      | python3 -c "import sys,json;print(len(json.load(sys.stdin)['data']['result']))")
  [ "$N" -eq 1 ]
  chk $? "4.4 revive 后恢复（实际 $N 条，应为 1）"
}

case "${1:-all}" in
  1) step1 ;;
  2) step2 ;;
  3) step3 ;;
  4) step4 ;;
  all) step1; step2; step3; step4 ;;
esac

echo
echo "===== 结果: PASS=$PASS FAIL=$FAIL ====="
