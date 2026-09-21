#!/usr/bin/env bash
# 终验：严格按修正后的讲义第四幕执行
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
OUT=$(mktemp /tmp/consul-final-XXXXXX.txt)
FAIL=0

pkill -f 'consul agent' 2>/dev/null; sleep 2
rm -rf $BASE/data/node{1,2,3}; mkdir -p $BASE/data/node{1,2,3}
for i in 1 2 3; do nohup consul agent -config-file $BASE/conf/node$i.hcl > $BASE/log/node$i.log 2>&1 & done
sleep 15

echo "########## 四关自检 ##########"
A=$(consul members | grep -c alive)
L=$(consul operator raft list-peers | grep -c leader)
H=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;print(json.load(sys.stdin)['Healthy'])")
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -d ok $CONSUL_HTTP_ADDR/v1/kv/_health)
VAL=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/_health?raw)
echo "1 alive=$A  2 leader=$L  3 Healthy=$H  4 write_http=$CODE read=$VAL"
[ "$A" = 3 ] && [ "$L" = 1 ] && [ "$H" = True ] && [ "$CODE" = 200 ] && [ "$VAL" = ok ] || { echo "!! FAIL 四关"; FAIL=1; }

echo
echo "########## 4a 停1台（sleep 8）##########"
pkill -f 'conf/node3.hcl'; sleep 8
W=$(curl -s --max-time 8 -X PUT -d 'after-1-down' $CONSUL_HTTP_ADDR/v1/kv/ops/quorum)
R=$(curl -s --max-time 8 $CONSUL_HTTP_ADDR/v1/kv/ops/quorum?raw)
echo "写=$W 读=$R"
[ "$W" = true ] && [ "$R" = "after-1-down" ] || { echo "!! FAIL 4a 讲义称可写"; FAIL=1; }

echo
echo "########## 4b 再停1台（sleep 8）##########"
pkill -f 'conf/node2.hcl'; sleep 8
succ=0
for i in 1 2 3 4; do
  code=$(curl -s -o "$OUT" -w '%{http_code}' --max-time 8 -X PUT -d 'x' $CONSUL_HTTP_ADDR/v1/kv/ops/quorum)
  body=$(head -c 40 "$OUT" | tr -d '\n')
  printf "  采样%d HTTP=%s body=[%s]\n" "$i" "$code" "$body"
  [ "$code" = "200" ] && succ=$((succ+1))
  sleep 1
done
echo "  成功次数=$succ (期望 0：讲义称不可写)"
[ "$succ" -eq 0 ] || { echo "!! FAIL 4b 讲义称不可写"; FAIL=1; }

echo
echo "  剩余 consul 进程 = $(pgrep -cf 'consul agent')  ← 进程活着但不可用（讲义核心论点）"

echo
echo "########## 恢复 ##########"
nohup consul agent -config-file $BASE/conf/node2.hcl > $BASE/log/node2.log 2>&1 &
nohup consul agent -config-file $BASE/conf/node3.hcl > $BASE/log/node3.log 2>&1 &
sleep 15
W4=$(curl -s --max-time 8 -X PUT -d 'recovered' $CONSUL_HTTP_ADDR/v1/kv/ops/quorum)
R4=$(curl -s --max-time 8 $CONSUL_HTTP_ADDR/v1/kv/ops/quorum?raw)
echo "写=$W4 读=$R4"
[ "$W4" = true ] && [ "$R4" = recovered ] || { echo "!! FAIL 恢复"; FAIL=1; }

rm -f "$OUT"
pkill -f 'consul agent' 2>/dev/null; sleep 2
echo
[ $FAIL -eq 0 ] && echo "=== 终验通过：讲义命令与结论均可照抄复现 ===" || echo "=== 终验失败 ==="
exit $FAIL
