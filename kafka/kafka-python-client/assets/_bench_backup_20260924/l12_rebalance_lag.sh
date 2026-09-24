#!/bin/bash
# 补测：rebalance 期间的 lag 与 fetch_state 变化（课12 遗留未测点）
# 场景：C1 独占 4 分区 -> C2 加入同组触发 rebalance -> C1 被剥夺一半分区
# 观测：cgrp 状态、fetch_state、stats.consumer_lag、手算 lag 在 rebalance 前后如何变
timeout 180 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import json, time, threading
from confluent_kafka import Consumer
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
GID=f"l12-reb-{int(time.time())%100000}"
def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

S1=[]
def stats1(s): S1.append(json.loads(s))

def mk(gid,cb):
    return Consumer({"bootstrap.servers":BROKERS,"group.id":gid,
                     "auto.offset.reset":"earliest","enable.auto.commit":True,
                     "auto.commit.interval.ms":300,
                     "statistics.interval.ms":300,"stats_cb":cb})
c1=mk(GID,stats1); c1.subscribe([TOPIC])

def lagof(c):
    out={}
    for tp in c.assignment():
        try:
            lo,hi=c.get_watermark_offsets(tp,timeout=5)
            cm=c.committed([tp],timeout=5)[0].offset
            if hi<0: continue
            out[tp.partition]=max(0,hi-(cm if cm and cm>=0 else 0))
        except Exception: pass
    return out

def snap(docs,label):
    if not docs: return
    d=docs[-1]; cg=d.get("cgrp",{})
    pl=d.get("topics",{}).get(TOPIC,{}).get("partitions",{})
    rows=[(v.get("partition"),v.get("fetch_state"),v.get("consumer_lag"))
          for v in pl.values() if isinstance(v,dict) and v.get("partition",-1)>=0]
    print(f"  {label}")
    print(f"    cgrp: state={cg.get('state')} join_state={cg.get('join_state')} "
          f"assignment_size={cg.get('assignment_size')} rebalance_cnt={cg.get('rebalance_cnt')}")
    for p,fs,lag in sorted(rows,key=lambda x:x[0]):
        print(f"      分区{p}: fetch_state={str(fs):<12} consumer_lag={lag}")

banner("① C1 独占 4 分区（steady 态基线）")
t0=time.time()
while time.time()-t0<15:
    c1.consume(num_messages=20,timeout=1)
    if c1.assignment() and S1 and S1[-1].get("cgrp",{}).get("join_state")=="steady": break
c1.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<1.5: c1.poll(0); time.sleep(0.1)
base_lag=lagof(c1)
snap(S1,"rebalance 前:")
print(f"    手算 lag: {base_lag}   合计 {sum(base_lag.values())}")

banner("② C2 加入同组 -> 触发 rebalance")
S2=[]; c2=mk(GID,lambda s: S2.append(json.loads(s)))
stop={"v":False}
def run_c2():
    c2.subscribe([TOPIC])
    while not stop["v"]:
        c2.consume(num_messages=10,timeout=1)
th=threading.Thread(target=run_c2,daemon=True); th.start()

# C1 持续 poll 让 rebalance 完成，记录整个过程的 join_state
seen=[]; base_cnt=1
if S1: base_cnt=S1[-1].get("cgrp",{}).get("rebalance_cnt",1)
t0=time.time()
while time.time()-t0<40:
    c1.consume(num_messages=10,timeout=1)
    if S1:
        cg=S1[-1].get("cgrp",{})
        js=cg.get("join_state")
        if not seen or seen[-1]!=js: seen.append(js)
        # 必须等 rebalance_cnt 真的增加（初始那次不算）
        if js=="steady" and cg.get("rebalance_cnt",0)>base_cnt and c1.assignment():
            break
time.sleep(2.0)
after_lag=lagof(c1)
snap(S1,"rebalance 后 (C1):")
print(f"    手算 lag: {after_lag}   合计 {sum(after_lag.values())}")
print(f"    join_state 变迁: {seen}")

banner("③ 关键对比")
print(f"  {'':<22}{'前':<28}{'后'}")
print(f"  {'分区数(手算覆盖)':<20}{str(len(base_lag)):<28}{len(after_lag)}")
print(f"  {'lag 合计(手算)':<20}{str(sum(base_lag.values())):<28}{sum(after_lag.values())}")
if S1:
    pl=S1[-1].get("topics",{}).get(TOPIC,{}).get("partitions",{})
    v={x.get("partition"):x.get("consumer_lag") for x in pl.values()
       if isinstance(x,dict) and x.get("partition",-1)>=0}
    nok=sum(1 for x in v.values() if x is not None and x>=0)
    print(f"  {'stats 有值分区':<20}{'?':<28}{nok}/{len(v)}")
lost=set(base_lag)-set(after_lag)
print(f"  被剥夺分区: {sorted(lost) if lost else '无'}")
print(f"\n  判据：被剥夺分区在 C1 侧【手算也拿不到】（不在 assignment 里）")
print(f"        -> lag 监控必须每个实例采集自己分区，再汇总；单点看不到全量")

banner("④ C2 侧视角（新成员分到的分区）")
if S2:
    snap(S2,"C2 快照:")
    print(f"    C2 手算 lag: {lagof(c2)}")
stop["v"]=True; time.sleep(0.5)
c1.close(); c2.close()
print(f"\n  已关闭，group={GID}")
PYEOF
