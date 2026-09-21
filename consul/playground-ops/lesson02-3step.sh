#!/usr/bin/env bash
# 三步核验铁律（沿用 Kafka 课 17）：值域 / 语义 / 连续采样
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

LIP=$(consul operator raft list-peers 2>/dev/null | awk '$4=="leader"{print $3}' | cut -d: -f1)
LNUM=$(echo "$LIP" | grep -oE '[0-9]+$' || echo 1)
LHTTP=$((8500+LNUM))

echo "leader = $LIP:$LHTTP"
echo
echo "########## 步骤1：curl 看实际值域 ##########"
echo "-- Prometheus 端点（consul_raft_state_leader）--"
for i in 1 2 3; do
  v=$(curl -s "http://$LIP:$LHTTP/v1/agent/metrics?format=prometheus" | grep -E '^consul_raft_state_leader ' | awk '{print $2}')
  echo "  采样$i: consul_raft_state_leader = ${v:-（无此行）}"
  sleep 2
done

echo
echo "-- 对比：consul_raft_apply（计数型，应该递增）--"
for i in 1 2 3; do
  v=$(curl -s "http://$LIP:$LHTTP/v1/agent/metrics?format=prometheus" | grep -E '^consul_raft_apply ' | awk '{print $2}')
  echo "  采样$i: consul_raft_apply = ${v:-（无此行）}"
  sleep 2
done

echo
echo "########## 步骤2：读 HELP 行确认语义 ##########"
curl -s "http://$LIP:$LHTTP/v1/agent/metrics?format=prometheus" | grep -B1 -E '^consul_(raft_state_leader|server_isLeader|autopilot_healthy) ' || echo "  无 HELP 行"

echo
echo "########## 步骤3：权威替代——用 API 而非指标判定 leader ##########"
echo "-- /v1/status/leader --"
curl -s "http://$LIP:$LHTTP/v1/status/leader"; echo
echo "-- raft list-peers 的 State 列 --"
consul operator raft list-peers | awk 'NR==1||$4=="leader"{print $1,$4}'

echo
echo "########## 关键对比：leader 节点 vs follower 节点的 isLeader ##########"
for i in 1 2 3; do
  v=$(curl -s "http://127.0.0.$i:$((8500+i))/v1/agent/metrics?format=prometheus" | grep -E '^consul_server_isLeader ' | awk '{print $2}')
  role=$(consul operator raft list-peers | awk -v n="ops-node-$i" '$1==n{print $4}')
  printf "  node$i (%s): consul_server_isLeader = %s\n" "$role" "${v:-无}"
done
