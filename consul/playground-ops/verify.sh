#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "===== 1. members ====="
consul members

echo
echo "===== 2. peers (Raft quorum) ====="
consul operator raft list-peers

echo
echo "===== 3. 各节点 server 角色 ====="
for p in 8501 8502 8503; do
  st=$(curl -s "http://127.0.0.$((p-8500)):$p/v1/status/leader")
  echo "node$((p-8500)) (http $p) -> leader=$st"
done

echo
echo "===== 4. catalog 节点数 ====="
curl -s http://127.0.0.1:8501/v1/catalog/nodes | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d),'nodes:',[n['Node'] for n in d])"
