#!/usr/bin/env bash
BASE=/tmp/consul-ops
for p in $(pgrep -x consul 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
sleep 2
mkdir -p "$BASE"/conf "$BASE"/log "$BASE"/data/node{1,2,3}
for i in 1 2 3; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null; done

for i in 1 2 3; do
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
done
echo "生成配置: $(ls -1 $BASE/conf/ | tr '\n' ' ')"
rm -rf "$BASE/data" "$BASE/log"; mkdir -p "$BASE"/data/node{1,2,3} "$BASE"/log
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 18
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
echo "进程数=$(pgrep -x consul | wc -l)"
consul operator raft list-peers 2>&1 | head -5
curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "import sys,json;d=json.load(sys.stdin);print('Healthy=',d['Healthy'],'FT=',d['FailureTolerance'])" 2>&1
