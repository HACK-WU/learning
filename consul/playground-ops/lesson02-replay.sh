#!/usr/bin/env bash
# 复验（修正脚本时序问题后）：重点验证 leave/failed 与多数派/少数派
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
FAIL=0

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

wait_alive() {
  local n=$1 want=$2
  for t in $(seq 1 20); do
    st=$(consul members -http-addr="http://127.0.0.2:8502" 2>/dev/null | awk -v x="ops-node-$n" '$1==x{print $3}')
    [ "$st" = "$want" ] && return 0
    sleep 1
  done
  return 1
}

echo "########## 验证 A：leave → left ##########"
clean_start
consul leave -http-addr=http://127.0.0.3:8503 >/dev/null 2>&1
sleep 6
ST3=$(consul members -http-addr=http://127.0.0.1:8501 | awk '/ops-node-3/{print $3}')
V=$(consul operator raft list-peers | grep -c 'ops-node')
echo "  状态=$ST3 (期望 left) ; voter 数=$V (期望 2)"
[ "$ST3" = "left" ] && [ "$V" = "2" ] || { echo "  !! FAIL A"; FAIL=1; }

echo
echo "########## 验证 B：强杀 → failed ##########"
clean_start
PID3=$(pgrep -f 'conf/node3.hcl')
kill -9 "$PID3"
sleep 8
ST3=$(consul members -http-addr=http://127.0.0.1:8501 | awk '/ops-node-3/{print $3}')
V=$(consul operator raft list-peers | grep -c 'ops-node')
echo "  状态=$ST3 (期望 failed) ; voter 数=$V (期望 3：failed 仍占名额，未清理)"
[ "$ST3" = "failed" ] || { echo "  !! FAIL B 状态"; FAIL=1; }
[ "$V" = "3" ] || echo "  （注意：voter 数=$V，与'failed 仍占名额'描述需复核）"

echo "  -- 等 autopilot 清理 --"
sleep 32
V2=$(consul operator raft list-peers | grep -c 'ops-node')
echo "  清理后 voter 数=$V2 (期望 2)"
[ "$V2" = "2" ] || { echo "  !! FAIL B 清理"; FAIL=1; }

echo
echo "########## 验证 C：多数派(2台) 可写 ##########"
clean_start
pkill -f 'conf/node3.hcl'; sleep 10
echo "  存活=$(pgrep -cf 'consul agent')"
for n in 1 2; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X PUT -d x "http://127.0.0.$n:$((8500+n))/v1/kv/ops/probe")
  echo "  node$n 写 HTTP=$c (期望 200)"
  [ "$c" = "200" ] || { echo "  !! FAIL C node$n"; FAIL=1; }
done

echo
echo "########## 验证 D：少数派(1台) 被拒 ##########"
ALIVE=$(pgrep -af 'consul agent' | grep -oE 'node[0-9]\.hcl' | grep -oE '[0-9]' | sort)
KEEP=$(echo "$ALIVE" | head -1)
DROP=$(echo "$ALIVE" | sed -n 2p)
pkill -f "conf/node$DROP.hcl"; sleep 10
echo "  存活=$(pgrep -cf 'consul agent') 保留 node$KEEP"
c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X PUT -d x "http://127.0.0.$KEEP:$((8500+KEEP))/v1/kv/ops/probe")
r=$(curl -s --max-time 5 "http://127.0.0.$KEEP:$((8500+KEEP))/v1/kv/ops/probe?raw")
echo "  少数派 node$KEEP 写 HTTP=$c (期望 500)"
echo "  少数派 读 = [${r:0:50}]"
[ "$c" = "500" ] || { echo "  !! FAIL D"; FAIL=1; }
echo "$r" | grep -q 'Raft leader not found' || echo "  （注意：读的报错是 [${r:0:40}]，与讲义描述需对照）"

pkill -f 'consul agent' 2>/dev/null; sleep 2
echo
[ $FAIL -eq 0 ] && echo "=== 复验通过 ===" || echo "=== 复验存在失败 ==="
exit $FAIL
