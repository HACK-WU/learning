#!/usr/bin/env bash
set -euo pipefail
BASE=/tmp/consul-ops

pkill -f 'consul agent' 2>/dev/null || true
sleep 2
rm -rf "$BASE"/data/node{1,2,3} "$BASE"/acl
mkdir -p "$BASE"/data/node{1,2,3} "$BASE"/acl

for i in 1 2 3; do
  cat > "$BASE/conf/node$i.hcl" <<EOF
node_name  = "ops-node-$i"
server     = true
datacenter = "opsdc1"
data_dir   = "$BASE/data/node$i"
log_level  = "INFO"

bind_addr      = "127.0.0.$i"
advertise_addr = "127.0.0.$i"
client_addr    = "127.0.0.$i"

bootstrap_expect = 3

ui_config {
  enabled = true
}

acl {
  enabled        = true
  default_policy = "deny"
  enable_token_persistence = true
}

telemetry {
  prometheus_retention_time = "60s"
}

ports {
  server       = $((8300 + i))
  serf_lan     = $((9300 + i))
  serf_wan     = -1
  http         = $((8500 + i))
  dns          = $((8600 + i))
  grpc         = $((8700 + i))
  grpc_tls     = $((8800 + i))
}

retry_join = ["127.0.0.1:9301", "127.0.0.2:9302", "127.0.0.3:9303"]
EOF
done

for i in 1 2 3; do
  nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 &
done
sleep 15
echo "started: $(pgrep -cf 'consul agent')"

export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
echo
echo "===== bootstrap ACL ====="
consul acl bootstrap > "$BASE/acl/boot.txt" 2>&1 || cat "$BASE/acl/boot.txt"
cat "$BASE/acl/boot.txt"
