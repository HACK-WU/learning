#!/usr/bin/env bash
# 知识点 2：节点上下线——三种方式的状态差异（left / failed / 自动清理）
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "########## A. 优雅下线 consul leave → 状态 left ##########"
LIP=$(consul operator raft list-peers | awk '$4=="leader"{print $3}' | cut -d: -f1)
LN=$(echo "$LIP" | grep -oE '[0-9]+$')
echo "先避开 leader（node$LN），下线 node3"
consul leave -http-addr=http://127.0.0.3:8503 2>&1 | head -2
sleep 6
echo "-- members --"
consul members
echo "-- raft peers（node3 是否已被移出 voter）--"
consul operator raft list-peers

echo
echo "########## B. 强杀 SIGKILL → 状态 failed（与 left 的区别）##########"
# 重启 node3 回到集群
nohup consul agent -config-file "$BASE/conf/node3.hcl" > "$BASE/log/node3.log" 2>&1 &
sleep 12
echo "-- node3 已重新加入 --"
consul members | grep node3

echo "-- 现在强杀 node3 --"
PID=$(pgrep -f 'conf/node3.hcl')
kill -9 "$PID"
sleep 8
echo "-- members（node3 应为 failed）--"
consul members
echo "-- raft peers --"
consul operator raft list-peers

echo
echo "########## C. autopilot 是否自动清理 dead server ##########"
echo "CleanupDeadServers 当前配置:"
consul operator autopilot get-config | grep Cleanup
echo "-- 等待 30s 观察 node3 是否被自动移出 voter --"
sleep 30
consul operator raft list-peers
echo "-- members --"
consul members
