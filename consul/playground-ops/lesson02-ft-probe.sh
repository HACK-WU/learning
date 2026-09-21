#!/usr/bin/env bash
# 核验：5 节点时 FailureTolerance 为什么还是 1？（反直觉，必须测准）
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

pkill -f 'consul agent' 2>/dev/null || true; sleep 2
rm -rf "$BASE"/data; mkdir -p "$BASE"/data/node{1,2,3,4,5} "$BASE"/log
for i in 1 2 3 4 5; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null || true; gen $i; done

show() {
  echo "  server 数 = $(consul operator raft list-peers 2>/dev/null | grep -c 'ops-node')"
  echo "  voter 数  = $(consul operator raft list-peers 2>/dev/null | awk '$5=="true"' | grep -c 'ops-node')"
  curl -s $CONSUL_HTTP_ADDR/v1/operator/autopilot/health | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  Healthy=',d['Healthy'],' FailureTolerance=',d['FailureTolerance'])
print('  Servers 详情:')
for s in d.get('Servers',[]):
    print(f\"    {s['Name']:12s} voter={str(s['Voter']):5s} healthy={s['Healthy']} lastContact={s['LastContact']}\")
"
}

echo "########## 3 节点 ##########"
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 15
show

echo
echo "########## 加到 5 节点，等 25s 让 autopilot 提升 voter ##########"
for i in 4 5; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 25
show

echo
echo "########## 再等 30s 复看（FailureTolerance 是否变化）##########"
sleep 30
show
