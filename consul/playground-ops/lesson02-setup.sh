#!/usr/bin/env bash
# 课 2 环境：干净的 3 节点基线（预留 node4/node5 用于 server 增删与脑裂演示）
set -euo pipefail
BASE=/tmp/consul-ops

pkill -f 'consul agent' 2>/dev/null || true
sleep 2

for i in 1 2 3 4 5; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null || true; done

rm -rf "$BASE"
mkdir -p "$BASE"/data/node{1,2,3,4,5} "$BASE"/conf "$BASE"/log

# 生成 N 个节点配置；bootstrap_expect 用参数指定（演示增删时需变化）
gen() {
  local i=$1 expect=$2
  cat > "$BASE/conf/node$i.hcl" <<EOF
node_name  = "ops-node-$i"
server     = true
datacenter = "opsdc1"
data_dir   = "$BASE/data/node$i"
log_level  = "INFO"

bind_addr      = "127.0.0.$i"
advertise_addr = "127.0.0.$i"
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

for i in 1 2 3; do gen $i 3; done

start() {
  for i in "$@"; do
    nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 &
  done
}

start 1 2 3
sleep 15
echo "启动进程数: $(pgrep -cf 'consul agent')"
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
consul members
consul operator raft list-peers
