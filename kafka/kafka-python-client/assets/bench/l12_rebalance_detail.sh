#!/bin/bash
# 正确复现：先灌消息造成真积压，再触发 rebalance
# 上次失败原因：C1 消费太快把积压吃光了，基线 lag 就是 0
# 本次：C1 停止消费 + 灌 5000 条 -> 确认 lag>0 -> 再让 C2 加入
timeout 240 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import json, time, threading
from confluent_kafka import Producer, Consumer
from confluent_kafka.admin import AdminClient, NewTopic
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")
a=AdminClient({"bootstrap.servers":BROKERS})
T=f"l12-reb2-{int(time.time())%100000}"
for t,f in a.create_topics([NewTopic(T,num_partitions=4,replication_factor=1)]).items(): f.result()
print(f"  新建 topic {T}（4 分区，全新无积压历史）")
GID=f"g{int(time.time())%100000}"
S=[]
c1=Consumer({"bootstrap.servers":BROKERS,"group.id":GID,"auto.offset.reset":"earliest",
             "enable.auto.commit":True,"auto.commit.interval.ms":300,
             "statistics.interval.ms":300,"stats_cb":lambda s:S.append(json.loads(s))})
try:
    c1.subscribe([T])
    t0=time.time()
    while time.time()-t0<15 and not c1.assignment(): c1.consume(num_messages=1,timeout=1)
    for _ in range(6):                    # 多消费几轮，确保有位移
        c1.consume(num_messages=5,timeout=1)
    try: c1.commit(asynchronous=False)
    except Exception as e: print(f"    (首次 commit 无位移，忽略: {type(e).__name__})")
    time.sleep(1)

    def detail(c,label):
        print(f"  {label}")
        print(f"    {'分区':<6}{'hi':>10}{'committed':>12}{'position':>10}{'fetch_state':>14}{'lag算':>10}")
        tot=0; fs={}
        if S:
            pl=S[-1].get("topics",{}).get(T,{}).get("partitions",{})
            fs={v.get("partition"):v.get("fetch_state") for v in pl.values()
                if isinstance(v,dict) and v.get("partition",-1)>=0}
        for tp in c.assignment():
            try:
                lo,hi=c.get_watermark_offsets(tp,timeout=5)
                cm=c.committed([tp],timeout=5)[0].offset
                po=c.position([tp])[0].offset
                off=cm if (cm and cm>=0) else 0
                lag=max(0,hi-off); tot+=lag
                print(f"    {tp.partition:<6}{hi:>10}{str(cm):>12}{str(po):>10}"
                      f"{str(fs.get(tp.partition)):>14}{lag:>10}")
            except Exception as e: print(f"    {tp.partition:<6} EXC {e}")
        print(f"    合计 lag = {tot}")
        return tot

    # 灌消息造成真积压（C1 不消费）
    banner("① 灌 5000 条消息，C1 不消费（制造真积压）")
    p=Producer({"bootstrap.servers":BROKERS,"linger.ms":0})
    for i in range(5000): p.produce(T, json.dumps({"i":i}).encode())
    p.flush(10); time.sleep(1)
    before=detail(c1,"积压后 C1（4 分区）:")

    banner("② C2 加入同组 -> 触发 rebalance")
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
    after=detail(c1,"rebalance 后 C1:")

    banner("③ 结论")
    print(f"  rebalance 前 lag = {before}  后 = {after}   差值 = {after-before}")
    print(f"  分区数: 4 -> {len(c1.assignment())}")
    print()
    print(f"  >> 若 lag 合计骤降但消息并未被消费：")
    print(f"     说明 rebalance 让『单实例视角的 lag』失真——被剥夺分区从视野消失")
    print(f"     而不是积压真的消失了。这是监控必须按【组】聚合而非【实例】的原因。")
    stop["v"]=True; time.sleep(0.5); c2.close()
finally:
    c1.close()
    try:
        for t,f in a.delete_topics([T]).items(): f.result()
        print(f"\n  清理 {T} ✓")
    except Exception as e: print(f"  清理失败 {e}")
PYEOF
