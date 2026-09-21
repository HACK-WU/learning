#!/usr/bin/env bash
BASE=/tmp/consul-ops
curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' > "$BASE/metrics.txt"

echo "===== 含 raft 的指标名 ====="
grep -o '^consul_raft[a-z_]*' "$BASE/metrics.txt" | sort -u

echo
echo "===== 含 runtime/serf/member 的指标名 ====="
grep -oE '^consul_(runtime|serf|member|autopilot|health)[a-z_]*' "$BASE/metrics.txt" | sort -u

echo
echo "===== 关键指标实际值（带标签）====="
grep -E '^consul_(raft_state|autopilot_healthy|autopilot_failure|server_isLeader|members_servers|members_clients|runtime_num_goroutines|runtime_alloc_bytes|runtime_heap_objects|runtime_sys_bytes)' "$BASE/metrics.txt" | head -20

echo
echo "===== leader 判断相关 ====="
grep -E 'isLeader|state_leader|state_follower' "$BASE/metrics.txt"

echo
echo "===== gc / 内存 ====="
grep -E '^consul_runtime' "$BASE/metrics.txt" | head -14
