#!/usr/bin/env bash
# 重测 A：leader 震荡恢复时间（探测节点要避开被杀的那个）
BASE=/tmp/consul-ops

pkill -f 'consul agent' 2>/dev/null || true
sleep 2
rm -rf "$BASE"/data/node{1,2,3}; mkdir -p "$BASE"/data/node{1,2,3}
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 15

probe_node() {
  # 在指定节点上尝试写，成功返回 0
  local n=$1
  local r
  r=$(curl -s --max-time 3 -X PUT -d "x" "http://127.0.0.$n:$((8500+n))/v1/kv/ops/probe" 2>/dev/null)
  [ "$r" = "true" ] && return 0 || return 1
}

alive_nodes() { pgrep -af 'consul agent' | grep -oE 'node[0-9]\.hcl' | grep -oE '[0-9]' | sort; }

for round in 1 2 3; do
  # 找一个存活且是 leader 的节点
  LNUM=""
  for n in $(alive_nodes); do
    st=$(consul operator raft list-peers -http-addr="http://127.0.0.$n:$((8500+n))" 2>/dev/null | awk -v x="ops-node-$n" '$1==x{print $4}')
    [ "$st" = "leader" ] && LNUM=$n && break
  done
  [ -z "$LNUM" ] && { echo "第$round轮：找不到 leader，跳过"; continue; }
  echo "第 $round 轮：leader = ops-node-$LNUM"

  pkill -f "conf/node$LNUM.hcl"
  START=$(date +%s%N)
  RECOVER=""
  # 在另一个存活节点上探测
  PROBE=$(alive_nodes | grep -v "^$LNUM$" | head -1)
  for t in $(seq 1 25); do
    sleep 1
    if probe_node "$PROBE"; then RECOVER=$t; break; fi
  done
  END=$(date +%s%N)
  if [ -n "$RECOVER" ]; then
    NEW=$(consul operator raft list-peers -http-addr="http://127.0.0.$PROBE:$((8500+PROBE))" 2>/dev/null | awk '$4=="leader"{print $1}')
    echo "   在 node$PROBE 上探测：${RECOVER}s 后恢复可写，新 leader = $NEW"
  else
    echo "   25s 内未恢复可写"
  fi

  # 重启被杀节点
  nohup consul agent -config-file "$BASE/conf/node$LNUM.hcl" > "$BASE/log/node$LNUM.log" 2>&1 &
  sleep 12
done

echo
echo "########## 最终状态 ##########"
consul operator raft list-peers -http-addr=http://127.0.0.1:8501
