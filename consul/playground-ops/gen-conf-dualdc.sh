#!/usr/bin/env bash
set -uo pipefail
BASE=/tmp/consul-ops/dualdc

pkill -f 'consul agent' 2>/dev/null || true
sleep 2
rm -rf "$BASE"
mkdir -p "$BASE"/data/dc1/node{1,2,3} "$BASE"/data/dc2/node1 "$BASE"/conf "$BASE"/log

# ---------- DC1: 3 server ----------
for i in 1 2 3; do
  UI="false"; [ "$i" = "1" ] && UI="true"
  cat > "$BASE/conf/dc1-s$i.hcl" <<EOF
node_name  = "dc1-s$i"
server     = true
datacenter = "dc1"
data_dir   = "$BASE/data/dc1/node$i"
log_level  = "INFO"

bind_addr      = "127.0.1.$i"
advertise_addr = "127.0.1.$i"
client_addr    = "127.0.1.$i"

bootstrap_expect = 3

ui_config { enabled = $UI }

ports {
  server   = 8300
  serf_lan = 8301
  serf_wan = 8302
  http     = 8500
  dns      = 8600
  grpc     = -1
  grpc_tls = -1
}

retry_join = ["127.0.1.1:8301", "127.0.1.2:8301", "127.0.1.3:8301"]
EOF
done

# ---------- DC2: 1 server ----------
cat > "$BASE/conf/dc2-s1.hcl" <<EOF
node_name  = "dc2-s1"
server     = true
datacenter = "dc2"
data_dir   = "$BASE/data/dc2/node1"
log_level  = "INFO"

bind_addr      = "127.0.2.1"
advertise_addr = "127.0.2.1"
client_addr    = "127.0.2.1"

bootstrap_expect = 1

ui_config { enabled = true }

ports {
  server   = 8300
  serf_lan = 8301
  serf_wan = 8302
  http     = 8500
  dns      = 8600
  grpc     = -1
  grpc_tls = -1
}

retry_join = ["127.0.2.1:8301"]
EOF

# ---------- 启动 ----------
for i in 1 2 3; do
  nohup consul agent -config-file "$BASE/conf/dc1-s$i.hcl" > "$BASE/log/dc1-s$i.log" 2>&1 &
done
nohup consul agent -config-file "$BASE/conf/dc2-s1.hcl" > "$BASE/log/dc2-s1.log" 2>&1 &
sleep 18

echo "进程数 = $(pgrep -fc 'consul agent')"

# ---------- WAN join（联邦的关键动作）----------
export CONSUL_HTTP_ADDR=http://127.0.1.1:8500
echo "--- WAN join 前 ---"
consul members -wan 2>&1 | sed 's/^/  /'
consul join -wan 127.0.2.1:8302 2>&1 | sed 's/^/  /'
sleep 8
echo "--- WAN join 后 ---"
consul members -wan 2>&1 | sed 's/^/  /'
echo "--- LAN (dc1) ---"
consul members 2>&1 | sed 's/^/  /'
