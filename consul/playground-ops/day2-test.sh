#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "===== 1. snapshot save ====="
consul snapshot save "$BASE/backup-$(date +%H%M%S).snap"
ls -lh "$BASE"/*.snap | tail -3

SNAP=$(ls -t "$BASE"/*.snap | head -1)
echo "--- inspect $SNAP ---"
consul snapshot inspect "$SNAP" 2>&1 | head -12

echo
echo "===== 2. autopilot 状态 ====="
consul operator autopilot get-config 2>&1
echo "--- health ---"
curl -s http://127.0.0.1:8501/v1/operator/autopilot/health | python3 -m json.tool 2>&1 | head -20

echo
echo "===== 3. 关键监控指标抽样 ====="
curl -s http://127.0.0.1:8501/v1/agent/metrics 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
g=d.get('Gauges',{})
c=d.get('Counters',{})
keys=['consul.raft.leader','consul.raft.state.leader','consul.raft.state.follower',
      'consul.raft.peers','consul.raft.commitTime','consul.raft.apply',
      'consul.runtime.alloc_bytes','consul.runtime.sys_bytes',
      'consul.runtime.num_goroutines','consul.runtime.heap_objects',
      'consul.serf.members','consul.serf.member.flap','consul.health.service.critical',
      'consul.health.service.passing','consul.catalog.service.query',
      'consul.kvs.apply','consul.raft.replication.appendEntries']
for k in keys:
    if k in g: print(f'{k:45s} = {g[k].get(\"Value\")}')
    elif k in c: print(f'{k:45s} = {c[k].get(\"Count\")} (counter)')
" 2>&1

echo
echo "===== 4. 关键指标总数 ====="
curl -s http://127.0.0.1:8501/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('Gauges:',len(d.get('Gauges',{})),'Counters:',len(d.get('Counters',{})),'Samples:',len(d.get('Samples',{})))
"
