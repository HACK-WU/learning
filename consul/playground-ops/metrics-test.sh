#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "===== Prometheus 格式指标（实际告警用的就是这个）====="
curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' > "$BASE/metrics.txt"
echo "总行数: $(wc -l < "$BASE/metrics.txt")"

python3 - "$BASE/metrics.txt" <<'PYEOF'
import sys,re
txt=open(sys.argv[1]).read()
want=['consul_raft_leader','consul_raft_state_leader','consul_raft_state_follower',
 'consul_raft_peers','consul_raft_commitTime','consul_raft_apply',
 'consul_runtime_alloc_bytes','consul_runtime_sys_bytes','consul_runtime_num_goroutines',
 'consul_runtime_heap_objects','consul_runtime_total_gc_pause_ns',
 'consul_serf_members','consul_serf_member_flap','consul_health_service_critical',
 'consul_health_service_passing','consul_catalog_service_query',
 'consul_kvs_apply','consul_raft_replication_appendEntries',
 'consul_autopilot_healthy','consul_autopilot_failure_tolerance',
 'consul_leader_barrier','consul_fsm_snapshot','consul_serf_events']
found={}
for line in txt.splitlines():
    if line.startswith('#'): continue
    m=re.match(r'^([a-zA-Z0-9_]+)',line)
    if not m: continue
    n=m.group(1)
    if n in want:
        found.setdefault(n,[]).append(line.split()[-1])
for k in want:
    if k in found:
        print(f'{k:42s} = {found[k][:4]}')
print()
print('--- 未出现的指标 ---')
print([k for k in want if k not in found])
PYEOF

echo
echo "===== 全部指标名前缀分布 ====="
cut -d'{' -f1 "$BASE/metrics.txt" | cut -d' ' -f1 | grep -v '^#' | grep -o '^consul_[a-z]*' | sort | uniq -c | sort -rn | head -15
