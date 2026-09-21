#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "===== D. 恢复 node2 + node3，看集群自愈 ====="
nohup consul agent -config-file "$BASE/conf/node2.hcl" > "$BASE/log/node2.log" 2>&1 &
nohup consul agent -config-file "$BASE/conf/node3.hcl" > "$BASE/log/node3.log" 2>&1 &
sleep 15

echo "-- members --"
consul members
echo "-- peers --"
consul operator raft list-peers
echo "-- 写 --"
curl -s -X PUT -d 'recovered' http://127.0.0.1:8501/v1/kv/ops/quorum && echo "  WRITE OK"
echo "-- 读 --"
curl -s http://127.0.0.1:8501/v1/kv/ops/quorum?raw; echo
