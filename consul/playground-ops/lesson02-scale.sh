#!/usr/bin/env bash
# 知识点 2 补充：server 扩容 3→5，以及 agent 反注册
BASE=/tmp/consul-ops

gen() {
  local i=$1 expect=$2
  cat > "$BASE/conf/node$i.hcl" <<EOF
node_name  = "ops-node-$i"
server     = true
datacenter = "opsdc1"
data_dir   = "$BASE/data/node$i"
log_level  = "INFO"
bind_addr      = "127.0.0.$i"
client_addr    = "127.0.0.$i"
bootstrap_expect = $expect
ui_config { enabled = true }
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

pkill -f 'consul agent' 2>/dev/null || true; sleep 2
rm -rf "$BASE"/data; mkdir -p "$BASE"/data/node{1,2,3,4,5} "$BASE"/log
for i in 1 2 3 4 5; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null || true; done

echo "########## 1. 起 3 节点（bootstrap_expect=3）##########"
for i in 1 2 3; do gen $i 3; done
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 15
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
consul operator raft list-peers
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('FailureTolerance=',d['FailureTolerance'])"

echo
echo "########## 2. 加 node4（server 扩容）##########"
gen 4 3
nohup consul agent -config-file "$BASE/conf/node4.hcl" > "$BASE/log/node4.log" 2>&1 &
sleep 12
echo "-- raft peers（node4 应先是非 voter，稳定后变 voter）--"
consul operator raft list-peers
echo "-- autopilot --"
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('FailureTolerance=',d['FailureTolerance'])"

echo
echo "########## 3. 加 node5 ##########"
gen 5 3
nohup consul agent -config-file "$BASE/conf/node5.hcl" > "$BASE/log/node5.log" 2>&1 &
sleep 12
consul operator raft list-peers
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('Healthy=',d['Healthy'],'FailureTolerance=',d['FailureTolerance'])"

echo
echo "########## 4. ServerStabilizationTime=10s，观察 voter 是否增长 ##########"
sleep 15
consul operator raft list-peers | awk 'NR>1{print "  "$1,$4,$5}'

echo
echo "########## 5. 缩容：优雅下线 node5、node4 回到 3 台 ##########"
consul leave -http-addr=http://127.0.0.5:8505 2>&1 | head -1
sleep 6
consul leave -http-addr=http://127.0.0.4:8504 2>&1 | head -1
sleep 6
consul operator raft list-peers
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('FailureTolerance=',d['FailureTolerance'])"
