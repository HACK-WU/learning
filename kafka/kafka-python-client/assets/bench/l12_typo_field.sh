#!/bin/bash
# 正测：subscribe() 真实进组 —— 这才是生产实况
# assign() 手动分配不进 cgrp（assignment_size=0），committed 拿不到
set -u
cat > /tmp/l12_sub.py <<'PYEOF'
import json, time
from confluent_kafka import Consumer, TopicPartition
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
docs=[]
def on_stats(s): docs.append(json.loads(s))
c=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
            "auto.offset.reset":"earliest","enable.auto.commit":True,
            "auto.commit.interval.ms":500,
            "statistics.interval.ms":500,"stats_cb":on_stats})
c.subscribe([TOPIC])
c.consume(num_messages=200,timeout=10)
c.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<4:
    c.poll(0); time.sleep(0.1)
print("="*74); print("subscribe() 实况：stats 能不能直接给 lag"); print("="*74)
d=docs[-1]; cg=d["cgrp"]
print(f"  cgrp.state={cg.get('state')}  join_state={cg.get('join_state')}  "
      f"assignment_size={cg.get('assignment_size')}  rebalance_cnt={cg.get('rebalance_cnt')}")
t=d["topics"][TOPIC]
parts=t.get("partitions",{})
print(f"  分区数: {len(parts)}")
print(f"\n  {'分区':<6}{'consumer_lag':>14}{'lag_stored':>12}{'hi':>8}{'commited(typo)':>16}{'committed':>11}{'fetch_state':>13}")
for pid,pv in parts.items():
    if not isinstance(pv,dict): continue
    print(f"  {pv.get('partition',pid):<6}{str(pv.get('consumer_lag')):>14}"
          f"{str(pv.get('consumer_lag_stored')):>12}{str(pv.get('hi_offset')):>8}"
          f"{str(pv.get('commited_offset')):>16}{str(pv.get('committed_offset')):>11}"
          f"{str(pv.get('fetch_state')):>13}")
# 交叉验证
print(f"\n{'─'*74}\n交叉验证：stats.consumer_lag vs 手算 hi-committed\n{'─'*74}")
asg=c.assignment()
cm=c.committed(asg,timeout=10) if asg else []
for tp in cm:
    lo,hi=c.get_watermark_offsets(tp,timeout=10)
    off=tp.offset if tp.offset and tp.offset>=0 else 0
    print(f"  分区{tp.partition}: hi={hi:<8} committed={tp.offset:<8} 手算lag={max(0,hi-off)}")
c.close()
PYEOF
docker cp /tmp/l12_sub.py l11:/sb.py >/dev/null
docker exec l11 /app/.venv/bin/python /sb.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -35
