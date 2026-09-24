#!/bin/bash
# 钉死两个雷：
#   R1. partitions 里 partition=-1 的幽灵条目（未分配占位，全 -1001）
#   R2. stats.consumer_lag 与即时手算 lag 的差值来源（采样时间差 or 口径不同）
set -u
cat > /tmp/l12_ghost.py <<'PYEOF'
import json, time
from confluent_kafka import Consumer
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
docs=[]
def on_stats(s): docs.append(json.loads(s))
c=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
            "auto.offset.reset":"earliest","enable.auto.commit":True,
            "auto.commit.interval.ms":300,
            "statistics.interval.ms":500,"stats_cb":on_stats})
c.subscribe([TOPIC])
c.consume(num_messages=100,timeout=10); c.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<3: c.poll(0); time.sleep(0.1)

print("="*74); print("R1. partition=-1 幽灵条目核验"); print("="*74)
parts=docs[-1]["topics"][TOPIC]["partitions"]
print(f"  partitions 条目数: {len(parts)}   (实际只有 4 个分区)")
bad=[];good=[]
for k,v in parts.items():
    if v.get("partition",-1) < 0: bad.append(k)
    else: good.append(k)
print(f"  有效分区: {len(good)}   幽灵条目(partition<0): {len(bad)} -> key={bad}")
if bad:
    g=parts[bad[0]]
    print(f"  幽灵条目内容: partition={g.get('partition')} hi={g.get('hi_offset')} "
          f"lag={g.get('consumer_lag')} fetch_state={g.get('fetch_state')}")
naive=sum(v.get("consumer_lag",-1) for v in parts.values())
safe =sum(v.get("consumer_lag",0) for v in parts.values() if v.get("partition",-1)>=0 and v.get("consumer_lag",-1)>=0)
print(f"\n  朴素聚合 sum(all consumer_lag)      = {naive}   <- 被 -1 污染")
print(f"  正确聚合 sum(partition>=0 且 lag>=0) = {safe}   <- 相差 {naive-safe}")

print(f"\n{'─'*74}\nR2. consumer_lag 口径：stats快照 vs 即时查询\n{'─'*74}")
# 连续取 3 次，看差值是否随消费推进而变（若是 -> 采样时间差，非 bug）
for i in range(3):
    d=docs[-1]
    pl=d["topics"][TOPIC]["partitions"]
    s_lag=[v.get("consumer_lag") for v in pl.values() if v.get("partition",-1)>=0]
    asg=c.assignment()
    cm=c.committed(asg,timeout=10) if asg else []
    now={}
    for tp in cm:
        lo,hi=c.get_watermark_offsets(tp,timeout=10)
        off=tp.offset if tp.offset and tp.offset>=0 else 0
        now[tp.partition]=max(0,hi-off)
    print(f"  第{i+1}次: stats={s_lag}  即时={[now.get(p) for p in sorted(now)]}")
    c.consume(num_messages=50,timeout=3); c.commit(asynchronous=False)
    t0=time.time()
    while time.time()-t0<1.2: c.poll(0); time.sleep(0.1)
print(f"\n  判定：若 stats 与即时值都随消费推进而变化 -> 采样时间差（正常）")
print(f"        stats 是 500ms 周期快照，committed() 是即时查询，必有偏差")
c.close()
PYEOF
docker cp /tmp/l12_ghost.py l11:/gh.py >/dev/null
docker exec l11 /app/.venv/bin/python /gh.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -40
