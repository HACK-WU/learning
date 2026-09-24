#!/bin/bash
# 消费者侧 stats 原始结构dump：确认 cgrp / topics 分区字段是否在
set -u
cat > /tmp/l12_dump.py <<'PYEOF'
import json, time, itertools
from confluent_kafka import Consumer, TopicPartition
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
GID="l12-dump-fixed"
docs=[]
def on_stats(s): docs.append(json.loads(s))
c=Consumer({"bootstrap.servers":BROKERS,"group.id":GID,
            "auto.offset.reset":"earliest","enable.auto.commit":True,
            "auto.commit.interval.ms":500,
            "statistics.interval.ms":500,"stats_cb":on_stats})
parts=[TopicPartition(TOPIC,i) for i in range(4)]
c.assign(parts)
c.consume(num_messages=100,timeout=5)
c.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<5:
    c.poll(0); time.sleep(0.1)
print("="*74); print(f"消费者侧 stats：共 {len(docs)} 份快照"); print("="*74)
if not docs: print("  ✗ 无快照"); raise SystemExit
d=docs[-1]
print(f"  顶层键: {sorted(d.keys())}")
print(f"  有 cgrp? {'cgrp' in d}")
if "cgrp" in d:
    cg=d["cgrp"]
    print(f"  cgrp 字段({len(cg)}): {sorted(cg.keys())}")
    for k in ["state","rebalance_cnt","assignment_size","commit_cnt","join_state"]:
        if k in cg: print(f"    {k:<18}= {cg[k]}")
print(f"\n  topics 键: {list(d.get('topics',{}).keys())}")
t=d.get("topics",{}).get(TOPIC,{})
print(f"  topic 级键: {sorted(t.keys())}")
for pid,pv in t.items():
    if not isinstance(pv,dict) or "partition" not in pv: continue
    print(f"\n  分区 {pv['partition']} 关键字段:")
    for k in ["lo_offset","hi_offset","ls_offset","app_offset","stored_offset",
              "commited_offset","committed_offset","consumer_lag","consumer_lag_stored","fetch_state"]:
        print(f"    {k:<22}= {pv.get(k)}")
    break
# 交叉验证
print(f"\n{'─'*74}\n交叉验证：stats.consumer_lag  vs  手算 hi-committed\n{'─'*74}")
cm=c.committed(parts,timeout=10)
for tp in cm:
    lo,hi=c.get_watermark_offsets(tp,timeout=10)
    off=tp.offset if tp.offset and tp.offset>=0 else 0
    print(f"  分区{tp.partition}: hi={hi:<8} committed={tp.offset:<8} 手算lag={max(0,hi-off)}")
c.close()
PYEOF
docker cp /tmp/l12_dump.py l11:/dp.py >/dev/null
docker exec l11 /app/.venv/bin/python /dp.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -45
