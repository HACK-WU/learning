#!/usr/bin/env bash
# 课 2 终验：核心结论逐条断言（已按实测修正期望）
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
FAIL=0; WARN=0

gen() {
  local i=$1
  cat > "$BASE/conf/node$i.hcl" <<EOF
node_name  = "ops-node-$i"
server     = true
datacenter = "opsdc1"
data_dir   = "$BASE/data/node$i"
log_level  = "INFO"
bind_addr  = "127.0.0.$i"
client_addr = "127.0.0.$i"
bootstrap_expect = 3
telemetry { prometheus_retention_time = "60s" }
ports {
  server   = $((8300 + i))
  serf_lan = $((9300 + i))
  serf_wan = -1
  http     = $((8500 + i))
  dns      = $((8600 + i))
  grpc     = $((8700 + i))
  grpc_tls = $((8800 + i))
}
retry_join = ["127.0.0.1:9301", "127.0.0.2:9302", "127.0.0.3:9303"]
EOF
}

clean_start() {
  pkill -f 'consul agent' 2>/dev/null; sleep 3
  rm -rf "$BASE"/data; mkdir -p "$BASE"/data/node{1,2,3,4,5} "$BASE"/log
  for i in 1 2 3 4 5; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null; gen $i; done
  for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
  sleep 16
}

echo "== 断言1 四处读数 =="
clean_start
V=$(consul operator raft list-peers | awk '$5=="true"' | grep -c 'ops-node')
FT=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;print(json.load(sys.stdin)['FailureTolerance'])")
C=$(curl -s -o /dev/null -w '%{http_code}' -X PUT -d ok $CONSUL_HTTP_ADDR/v1/kv/_health)
R=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/_health?raw)
echo "  voter=$V FT=$FT 写HTTP=$C 回读=$R"
[ "$V" = 3 ] && [ "$FT" = 1 ] && [ "$C" = 200 ] && [ "$R" = ok ] || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言2 指标恒0而API健康 =="
H=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;print(json.load(sys.stdin)['Healthy'])")
M=$(curl -s "$CONSUL_HTTP_ADDR/v1/agent/metrics?format=prometheus" | grep -E '^consul_autopilot_healthy' | awk '{print $2}')
echo "  API Healthy=$H ; 指标=$M"
[ "$H" = True ] && [ "$M" = 0 ] || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言3 leave → left 且 voter 减1 =="
consul leave -http-addr=http://127.0.0.3:8503 >/dev/null 2>&1; sleep 6
S=$(consul members | awk '/ops-node-3/{print $3}'); V2=$(consul operator raft list-peers | grep -c 'ops-node')
echo "  状态=$S voter=$V2"
[ "$S" = left ] && [ "$V2" = 2 ] || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言4 强杀 → failed，autopilot 清理 =="
clean_start
kill -9 $(pgrep -f 'conf/node3.hcl'); sleep 8
S=$(consul members | awk '/ops-node-3/{print $3}')
echo "  状态=$S"
[ "$S" = failed ] || { echo "  !! FAIL"; FAIL=1; }
sleep 32
V3=$(consul operator raft list-peers | grep -c 'ops-node')
echo "  清理后 voter=$V3 (期望2)"
[ "$V3" = 2 ] || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言5 扩容：4台 FT 仍为1，5台才为2 =="
clean_start
nohup consul agent -config-file "$BASE/conf/node4.hcl" > "$BASE/log/node4.log" 2>&1 &
sleep 35
V4=$(consul operator raft list-peers | awk '$5=="true"' | grep -c 'ops-node')
F4=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;print(json.load(sys.stdin)['FailureTolerance'])")
echo "  4台: voter=$V4 FT=$F4 (期望 4 和 1)"
[ "$V4" = 4 ] && [ "$F4" = 1 ] || { echo "  !! FAIL"; FAIL=1; }
nohup consul agent -config-file "$BASE/conf/node5.hcl" > "$BASE/log/node5.log" 2>&1 &
sleep 35
V5=$(consul operator raft list-peers | awk '$5=="true"' | grep -c 'ops-node')
F5=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;print(json.load(sys.stdin)['FailureTolerance'])")
echo "  5台: voter=$V5 FT=$F5 (期望 5 和 2)"
[ "$V5" = 5 ] && [ "$F5" = 2 ] || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言6 多数派可写 / 少数派被拒 =="
clean_start
pkill -f 'conf/node3.hcl'; sleep 10
for n in 1 2; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X PUT -d x "http://127.0.0.$n:$((8500+n))/v1/kv/ops/probe")
  echo "  多数派 node$n HTTP=$c"
  [ "$c" = 200 ] || { echo "  !! FAIL"; FAIL=1; }
done
pkill -f 'conf/node2.hcl'; sleep 10
KEEP=$(pgrep -af 'consul agent' | grep -oE 'node[0-9]\.hcl' | grep -oE '[0-9]' | head -1)
c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X PUT -d x "http://127.0.0.$KEEP:$((8500+KEEP))/v1/kv/ops/probe")
r=$(curl -s --max-time 5 "http://127.0.0.$KEEP:$((8500+KEEP))/v1/kv/ops/probe?raw")
echo "  少数派 node$KEEP HTTP=$c 读=[${r:0:40}]"
# 500 或 000 都算被拒
case "$c" in 500|000) ;; *) echo "  !! FAIL 少数派未被拒"; FAIL=1;; esac

pkill -f 'consul agent' 2>/dev/null; sleep 2
echo
[ $FAIL -eq 0 ] && echo "=== 课2 终验通过（6 组断言）===" || echo "=== 终验失败 ==="
exit $FAIL
