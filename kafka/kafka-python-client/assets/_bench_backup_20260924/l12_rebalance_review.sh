#!/bin/bash
# 补测复审：rebalance 三条新结论逐条核验
timeout 240 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import json, time, threading
from confluent_kafka import Producer, Consumer
from confluent_kafka.admin import AdminClient, NewTopic
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
P=F=0
def chk(d,c,ev=""):
    global P,F
    if c: P+=1; print(f"  ✓ {d}")
    else: F+=1; print(f"  ✗ {d}   <<< {ev}")
print("="*74); print("课12 补测复审：rebalance 结论核验"); print("="*74)
a=AdminClient({"bootstrap.servers":BROKERS})
T=f"l12-rv2-{int(time.time())%100000}"
for t,f in a.create_topics([NewTopic(T,num_partitions=4,replication_factor=1)]).items(): f.result()
GID=f"g{int(time.time())%100000}"
S=[]
c1=Consumer({"bootstrap.servers":BROKERS,"group.id":GID,"auto.offset.reset":"earliest",
             "enable.auto.commit":True,"auto.commit.interval.ms":300,
             "statistics.interval.ms":300,"stats_cb":lambda s:S.append(json.loads(s))})
try:
    c1.subscribe([T])
    t0=time.time()
    while time.time()-t0<20:
        c1.consume(num_messages=1,timeout=1)
        if len(c1.assignment())==4: break      # 等 4 个分区全部分配
    chk0=len(c1.assignment())
    print(f"  等待后已分配分区数: {chk0}")
    for _ in range(6): c1.consume(num_messages=5,timeout=1)
    try: c1.commit(asynchronous=False)
    except Exception: pass
    time.sleep(1.5)
    # 造积压
    p=Producer({"bootstrap.servers":BROKERS,"linger.ms":0})
    for i in range(5000): p.produce(T,json.dumps({"i":i}).encode())
    p.flush(10); time.sleep(1)
    def lagof(c):
        tot=0; n=0
        for tp in c.assignment():
            try:
                lo,hi=c.get_watermark_offsets(tp,timeout=5)
                cm=c.committed([tp],timeout=5)[0].offset
                if hi<0: continue
                tot+=max(0,hi-(cm if cm and cm>=0 else 0)); n+=1
            except Exception: pass
        return tot,n
    b_tot,b_n=lagof(c1)
    chk("结论13a 积压已造成(lag>4000)", b_tot>4000, f"={b_tot}")
    chk("结论13b rebalance 前覆盖 4 分区", b_n==4, f"={b_n}")
    # rebalance
    c2=Consumer({"bootstrap.servers":BROKERS,"group.id":GID,"auto.offset.reset":"earliest",
                 "enable.auto.commit":True,"auto.commit.interval.ms":300})
    stop={"v":False}
    def run():
        c2.subscribe([T])
        while not stop["v"]: c2.consume(num_messages=5,timeout=1)
    threading.Thread(target=run,daemon=True).start()
    base=S[-1]["cgrp"].get("rebalance_cnt",1) if S else 1
    t0=time.time()
    while time.time()-t0<40:
        c1.poll(0); time.sleep(0.05)
        if S:
            cg=S[-1]["cgrp"]
            if cg.get("join_state")=="steady" and cg.get("rebalance_cnt",0)>base and c1.assignment():
                break
    time.sleep(1.5)
    a_tot,a_n=lagof(c1)
    chk("结论13c rebalance 后分区数减少", a_n<b_n, f"{b_n}->{a_n}")
    chk("结论13d lag 合计骤降", a_tot<b_tot, f"{b_tot}->{a_tot}")
    # position -1001
    neg=0
    for tp in c1.assignment():
        try:
            if c1.position([tp])[0].offset<0: neg+=1
        except Exception: pass
    chk("结论15 rebalance 后 position 为负", neg>=1, f"负值分区={neg}")
    # cgrp rebalance_cnt 真的增加了
    rc=S[-1]["cgrp"].get("rebalance_cnt",0) if S else 0
    chk("结论13e rebalance_cnt 增加", rc>base, f"{base}->{rc}")
    stop["v"]=True; time.sleep(0.5); c2.close()
finally:
    c1.close()
    try:
        for t,f in a.delete_topics([T]).items(): f.result()
    except Exception: pass
print("\n"+"="*74); print(f"  通过 {P}  失败 {F}"); print("="*74)
PYEOF
