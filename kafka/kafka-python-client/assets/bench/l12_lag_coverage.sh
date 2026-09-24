#!/bin/bash
# 决定性实验：stats.consumer_lag 到底覆盖哪些分区？
# 假设：只覆盖「当前正在 fetch 且已收到 fetch 响应」的分区，其余为 -1
# 验证手法：让消费者真正从所有分区消费，看 -1 是否消失
set -u
cat > /tmp/l12_cov.py <<'PYEOF'
import json, time
from confluent_kafka import Consumer
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
docs=[]
def on_stats(s): docs.append(json.loads(s))
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"l12-cov-{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":True,
            "auto.commit.interval.ms":300,"statistics.interval.ms":500,
            "stats_cb":on_stats})
c.subscribe([TOPIC])

def snap(label):
    t0=time.time()
    while time.time()-t0<1.5: c.poll(0); time.sleep(0.1)
    if not docs: return
    pl=docs[-1]["topics"][TOPIC]["partitions"]
    rows=[(v.get("partition"),v.get("consumer_lag"),v.get("fetch_state"),v.get("hi_offset"))
          for v in pl.values() if isinstance(v,dict)]
    rows=[r for r in rows if r[0] is not None and r[0]>=0]
    print(f"  {label}")
    for p,lag,fs,hi in sorted(rows,key=lambda x:x[0]):
        flag="" if (lag is not None and lag>=0) else "   <- lag=-1 无值"
        print(f"    分区{p}: lag={str(lag):<8} fetch_state={str(fs):<10} hi={hi}{flag}")

print("="*74); print("stats.consumer_lag 覆盖范围实验"); print("="*74)
# 阶段1：只消费少量（大部分分区未被 fetch 到）
c.consume(num_messages=20,timeout=5); c.commit(asynchronous=False)
snap("阶段1 · 仅消费 20 条（只有部分分区被 fetch）")
# 阶段2：充分消费，让每个分区都被 fetch
for _ in range(12):
    c.consume(num_messages=300,timeout=3)
    c.commit(asynchronous=False)
snap("阶段2 · 充分消费 3600 条（每分区都 fetch 过）")
# 阶段3：暂停消费，看 lag 是否回退成 -1
t0=time.time()
while time.time()-t0<2:
    c.poll(0); time.sleep(0.1)
snap("阶段3 · 停止消费 2s 后")

print(f"\n{'─'*74}\n结论判定\n{'─'*74}")
if docs:
    pl=docs[-1]["topics"][TOPIC]["partitions"]
    vals=[v.get("consumer_lag") for v in pl.values()
          if isinstance(v,dict) and v.get("partition",-1)>=0]
    ok=[v for v in vals if v is not None and v>=0]
    print(f"  最终快照 lag 值: {vals}")
    print(f"  有值分区 {len(ok)}/{len(vals)}")
    print(f"  -> 若 <全部：stats 只覆盖活跃 fetch 分区，全量 lag 必须用 committed()+watermark 手算")
c.close()
PYEOF
docker cp /tmp/l12_cov.py l11:/cv.py >/dev/null
docker exec l11 /app/.venv/bin/python /cv.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -40
