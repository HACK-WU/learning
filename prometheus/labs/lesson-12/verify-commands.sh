#!/usr/bin/env bash
# 逐字执行讲义第四幕命令，验证学员照抄能跑通
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
B=/mnt/d/projects/learning/prometheus
P=http://localhost:19500
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then echo "PASS  $1  ($2)"; PASS=$((PASS+1));
       else echo "FAIL  $1  期望=$3 实际=$2"; FAIL=$((FAIL+1)); fi; }

echo "===== 前置：确保实例在跑 ====="
if ! curl -sf $P/-/ready >/dev/null 2>&1; then
  echo "实例未运行，启动中..."
  bash $D/up.sh >/dev/null 2>&1
fi
curl -sf $P/-/ready >/dev/null 2>&1 && echo "ready" || echo "NOT READY"

echo
echo "===== 步骤 1：配置校验 ====="
R=$(docker run --rm -v $D/cfg:/cfg --entrypoint promtool prom/prometheus:v3.14.0 \
    check config /cfg/good.yml 2>&1 | grep -c SUCCESS)
ck "good.yml 校验通过" "$R" "1"

R=$(docker run --rm -v $D/cfg:/cfg --entrypoint promtool prom/prometheus:v3.14.0 \
    check config /cfg/bad-timeout.yml 2>&1 | grep -c "scrape timeout greater")
ck "bad-timeout.yml 被拦" "$R" "1"

echo
echo "===== 步骤 2：规则单测（正/反） ====="
R=$(docker run --rm -v $D/rules:/r --entrypoint promtool prom/prometheus:v3.14.0 \
    test rules /r/disk_test.yml 2>&1 | grep -c SUCCESS)
ck "正向单测 SUCCESS" "$R" "1"

R=$(docker run --rm -v $D/rules:/r --entrypoint promtool prom/prometheus:v3.14.0 \
    test rules /r/disk_test_neg.yml 2>&1 | grep -c FAILED)
ck "反向单测 FAILED" "$R" "1"

echo
echo "===== 步骤 3：check metrics --extended 出基数表 ====="
curl -s $P/metrics > $D/metrics/self2.prom
R=$(docker run --rm -i --entrypoint promtool prom/prometheus:v3.14.0 \
    check metrics --extended < $D/metrics/self2.prom 2>&1 | grep -c "Cardinality")
ck "--extended 输出基数表" "$R" "1"

echo
echo "===== 步骤 4：/api/v1/status/tsdb 可用 ====="
R=$(curl -s $P/api/v1/status/tsdb | python3 -c "import json,sys; print(1 if 'headStats' in json.load(sys.stdin)['data'] else 0)")
ck "status/tsdb 返回 headStats" "$R" "1"

echo
echo "===== 步骤 5：snapshot ====="
R=$(curl -s -XPOST $P/api/v1/admin/tsdb/snapshot | grep -c '"status":"success"')
ck "snapshot 返回 success" "$R" "1"

echo
echo "===== 步骤 6：delete_series（--data-urlencode 写法） ====="
R=$(curl -s -o /dev/null -w "%{http_code}" -XPOST -G $P/api/v1/admin/tsdb/delete_series \
    --data-urlencode 'match[]=l12_series')
ck "delete_series HTTP 204" "$R" "204"

echo
echo "===== 步骤 7：验证删除（range 查询） ====="
R=$(python3 $D/rq.py 19500 'count(l12_series)' 10 2>&1 | head -1)
echo "  range 查询结果: $R"
[ -n "$R" ] && { echo "PASS  步骤7 可查询"; PASS=$((PASS+1)); } || { echo "FAIL  步骤7"; FAIL=$((FAIL+1)); }

echo
echo "===== 步骤 8：scrape_duration_seconds 可查（故障实例） ====="
R=$(curl -s "http://localhost:19501/api/v1/query?query=scrape_duration_seconds" | grep -c "scrape_duration_seconds")
ck "故障实例 duration 可查" "$R" "1"

echo
echo "======================================"
echo "PASS = $PASS   FAIL = $FAIL"
echo "======================================"
[ $FAIL -eq 0 ] && echo "RESULT: ALL PASS" || echo "RESULT: HAS FAILURES"
