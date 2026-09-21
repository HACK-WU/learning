#!/usr/bin/env bash
# 复验扩容：给足时间，观察 voter 提升与 FailureTolerance 变化
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

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

pkill -f 'consul agent' 2>/dev/null; sleep 3
rm -rf "$BASE"/data; mkdir -p "$BASE"/data/node{1,2,3,4,5} "$BASE"/log
for i in 1 2 3 4 5; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null; gen $i; done
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 16

snap() {
  local tag=$1
  local s v ft
  s=$(consul operator raft list-peers 2>/dev/null | grep -c 'ops-node' || echo 0)
  v=$(consul operator raft list-peers 2>/dev/null | awk '$5=="true"' | grep -c 'ops-node' || echo 0)
  ft=$(curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['FailureTolerance'])" 2>/dev/null || echo NA)
  printf "  %-28s server=%s voter=%s FailureTolerance=%s\n" "$tag" "$s" "$v" "$ft"
}

snap "初始 3 台"

echo
echo "########## 加 node4 ##########"
nohup consul agent -config-file "$BASE/conf/node4.hcl" > "$BASE/log/node4.log" 2>&1 &
sleep 10; snap "node4 加入 +10s"
sleep 15; snap "node4 加入 +25s"
sleep 15; snap "node4 加入 +40s"

echo
echo "########## 加 node5 ##########"
nohup consul agent -config-file "$BASE/conf/node5.hcl" > "$BASE/log/node5.log" 2>&1 &
sleep 10; snap "node5 加入 +10s"
sleep 20; snap "node5 加入 +30s"
sleep 20; snap "node5 加入 +50s"
sleep 20; snap "node5 加入 +70s"

echo
echo "########## 最终 raft ##########"
consul operator raft list-peers | awk 'NR>1{printf "  %s %s voter=%s\n",$1,$4,$5}'

pkill -f 'consul agent' 2>/dev/null; sleep 2
echo "已清理"
