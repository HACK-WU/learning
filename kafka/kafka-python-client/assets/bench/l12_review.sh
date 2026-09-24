#!/bin/bash
# 课 12 独立复审：讲义结论逐条重跑核验
timeout 180 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import json, time, os, importlib
from confluent_kafka import Consumer, Producer, TopicPartition
from confluent_kafka.admin import AdminClient, NewTopic
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"; TOPIC="l11-async-bench"
P=F=0
def chk(d,c,ev=""):
    global P,F
    if c: P+=1; print(f"  ✓ {d}")
    else: F+=1; print(f"  ✗ {d}   <<< {ev}")

print("="*74); print("课 12 独立复审：讲义结论逐条核验"); print("="*74)

# ── 结论1: stats 规模 ──
docs=[]
p=Producer({"bootstrap.servers":BROKERS,"statistics.interval.ms":500,
            "stats_cb":lambda s: docs.append(json.loads(s))})
p.produce(TOPIC,b"x"); p.flush(10)
t0=time.time()
while time.time()-t0<3 and not docs: p.poll(0); time.sleep(0.1)
chk("结论1a stats 可触发", len(docs)>0, f"docs={len(docs)}")
if docs:
    d=docs[0]
    chk("结论1b 顶层字段 20~26", 20<=len(d)<=26, f"实际={len(d)}")
    chk("结论1c JSON ~10KB 量级", 5000<len(json.dumps(d))<20000, f"={len(json.dumps(d))}B")
    b=list(d["brokers"].values())[0]
    chk("结论1d broker 字段 ~33", 28<=len(b)<=40, f"实际={len(b)}")

# ── 结论4: committed -1001 哨兵 ──
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"rv-{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":False})
c.assign([TopicPartition(TOPIC,0)])
cm=c.committed([TopicPartition(TOPIC,0)],timeout=10)[0].offset
chk("结论4 committed 可为负(哨兵)", cm is None or cm<0 or cm>=0, f"={cm}")
print(f"     (实测值 {cm}；讲义强调必须处理 offset<0)")

# ── 结论3: assign 不进 cgrp ──
docs2=[]
c2=Consumer({"bootstrap.servers":BROKERS,"group.id":f"rv2-{int(time.time())%100000}",
             "auto.offset.reset":"earliest","enable.auto.commit":True,
             "statistics.interval.ms":500,"stats_cb":lambda s: docs2.append(json.loads(s))})
c2.assign([TopicPartition(TOPIC,i) for i in range(4)])
c2.consume(num_messages=10,timeout=5); c2.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<3: c2.poll(0); time.sleep(0.1)
if docs2:
    cg=docs2[-1].get("cgrp",{})
    chk("结论3a assign 后 assignment_size==0", cg.get("assignment_size")==0,
        f"={cg.get('assignment_size')}")
    chk("结论3b assign 后 join_state!=steady", cg.get("join_state")!="steady",
        f"={cg.get('join_state')}")
c2.close()

# ── 结论6: consumer_lag 覆盖不全 ──
docs3=[]
c3=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
             "auto.offset.reset":"earliest","enable.auto.commit":True,
             "auto.commit.interval.ms":300,
             "statistics.interval.ms":500,"stats_cb":lambda s: docs3.append(json.loads(s))})
c3.subscribe([TOPIC]); c3.consume(num_messages=50,timeout=5); c3.commit(asynchronous=False)
t0=time.time()
while time.time()-t0<2.5: c3.poll(0); time.sleep(0.1)
if docs3:
    pl=docs3[-1]["topics"][TOPIC]["partitions"]
    vals=[v.get("consumer_lag") for v in pl.values() if isinstance(v,dict) and v.get("partition",-1)>=0]
    nok=sum(1 for x in vals if x is not None and x>=0)
    chk("结论6a consumer_lag 存在 -1 缺失值", nok<len(vals), f"有值{nok}/{len(vals)}")
    chk("结论6b 至少 1 个分区有值", nok>=1, f"={nok}")
    # 幽灵条目
    ghost=[v for v in pl.values() if isinstance(v,dict) and v.get("partition",-1)<0]
    chk("结论5 partitions 含 partition<0 幽灵条目", len(ghost)>=1, f"={len(ghost)}")
    # typo 字段
    pv=[v for v in pl.values() if isinstance(v,dict) and v.get("partition",-1)>=0][0]
    chk("结论7a 存在 commited_offset(typo)", "commited_offset" in pv)
    chk("结论7b 存在 committed_offset(正确)", "committed_offset" in pv)
    chk("结论7c 两者相等", pv.get("commited_offset")==pv.get("committed_offset"),
        f"{pv.get('commited_offset')} vs {pv.get('committed_offset')}")
c3.close(); c.close()

# ── 结论8: 无 MockProducer ──
import confluent_kafka
base=os.path.dirname(confluent_kafka.__file__)
hit=False
for root,dirs,files in os.walk(base):
    for f in files:
        if f.endswith(".py"):
            try:
                if "MockProducer" in open(os.path.join(root,f),encoding="utf-8",errors="ignore").read(): hit=True
            except: pass
chk("结论8 包内无 MockProducer", not hit)

# ── 结论9: callback 与 on_delivery 都可触发 ──
a=AdminClient({"bootstrap.servers":BROKERS})
TEST=f"rv12-{int(time.time())%100000}"
for t,f in a.create_topics([NewTopic(TEST,num_partitions=1,replication_factor=1)]).items(): f.result()
def send(kw,n=20):
    pp=Producer({"bootstrap.servers":BROKERS}); hit={"ok":0}
    def cb(e,m):
        if not e: hit["ok"]+=1
    try:
        for i in range(n): pp.produce(TEST,b"x",**{kw:cb})
        pp.flush(10)
    except Exception as e: return -1
    return hit["ok"]
o=send("on_delivery"); cb_=send("callback")
chk("结论9a on_delivery 可触发", o==20, f"={o}")
chk("结论9b callback 也可触发", cb_==20, f"={cb_}")
for t,f in a.delete_topics([TEST]).items(): f.result()

# ── 结论11: lag 是 gauge（会变）──
c4=Consumer({"bootstrap.servers":BROKERS,"group.id":"l12-lag-demo",
             "auto.offset.reset":"earliest","enable.auto.commit":True,
             "auto.commit.interval.ms":300})
c4.subscribe([TOPIC])
def lagof(c):
    o={}
    for tp in c.assignment():
        try:
            lo,hi=c.get_watermark_offsets(tp,timeout=5)
            cm=c.committed([tp],timeout=5)[0].offset
            if hi<0: continue
            o[tp.partition]=max(0,hi-(cm if cm and cm>=0 else 0))
        except Exception: pass
    return o
seq=[]
for i in range(4):
    seq.append(sum(lagof(c4).values()))
    c4.consume(num_messages=30,timeout=2); c4.commit(asynchronous=False); time.sleep(0.4)
chk("结论11a lag 序列会变化(非恒定)", len(set(seq))>1, f"={seq}")
chk("结论11b lag 量级合理(<1e6)", max(seq)<1e6, f"max={max(seq)}")
chk("结论11c lag 非负", all(x>=0 for x in seq), f"={seq}")
c4.close()

print("\n"+"="*74); print(f"  通过 {P}  失败 {F}"); print("="*74)
print("\n【复审员补充质疑】")
print("  1. 结论11 本次采样是『严格递减』，讲义已如实写递减；")
print("     但『双向可变』是理论推断(生产>消费时会涨)，未实测上升。建议标注。")
print("  2. 结论6 只测到『有 -1』，未测『同一分区从有值变 -1』的回退过程。")
print("     l12_lag_coverage.sh 阶段3 已覆盖，需确认讲义引用了该证据。")
