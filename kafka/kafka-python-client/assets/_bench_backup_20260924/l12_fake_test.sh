#!/bin/bash
# 修正版 Fake：同时接受 on_delivery 和 callback（与真实 API 一致）
# 并演示「假绿」陷阱：fake 签名比真实 API 严格时，测试通过但零断言
timeout 60 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import json, time
from confluent_kafka import Producer, Consumer, TopicPartition
from confluent_kafka.admin import AdminClient, NewTopic
def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

banner("坑：Fake 签名比真实 API 严格 -> 测试假绿")
class StrictFake:                     # 只认 on_delivery（我第一版写的）
    def __init__(self): self.q=[]; self.pending=0
    def produce(self,topic,value=None,key=None,on_delivery=None,**kw):
        self.pending+=1; self.q.append({"cb":on_delivery,"acked":False})
    def flush(self,t=10):
        for m in self.q:
            if not m["acked"]:
                if m["cb"]: m["cb"](None,None)
                m["acked"]=True; self.pending-=1
class LooseFake:                      # 与真实一致：两个名字都收
    def __init__(self): self.q=[]; self.pending=0
    def produce(self,topic,value=None,key=None,on_delivery=None,callback=None,**kw):
        cb=on_delivery or callback
        self.pending+=1; self.q.append({"cb":cb,"acked":False})
    def flush(self,t=10):
        for m in self.q:
            if not m["acked"]:
                if m["cb"]: m["cb"](None,None)
                m["acked"]=True; self.pending-=1

def business(producer,n,topic,style):
    st={"ok":0}
    def cb(err,msg):
        if not err: st["ok"]+=1
    for i in range(n):
        if style=="callback": producer.produce(topic,json.dumps({"i":i}).encode(),callback=cb)
        else:                 producer.produce(topic,json.dumps({"i":i}).encode(),on_delivery=cb)
    producer.flush(10)
    return st["ok"]

for name,fk in [("StrictFake",StrictFake),("LooseFake",LooseFake)]:
    for style in ["callback","on_delivery"]:
        p=fk(); n=business(p,100,"t",style)
        mark="  <- 假绿！" if n==0 else ""
        print(f"  {name:<12}+{style:<12} -> cb 触发 {n:>4}/100{mark}")

banner("层2 · 真集群：同业务代码，真实语义")
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
a=AdminClient({"bootstrap.servers":BROKERS})
TEST=f"l12-f-{int(time.time())%100000}"
for t,f in a.create_topics([NewTopic(TEST,num_partitions=3,replication_factor=1)]).items(): f.result()
rp=Producer({"bootstrap.servers":BROKERS})
t0=time.perf_counter(); n=business(rp,300,TEST,"callback")
print(f"  真集群 callback 风格: {n}/300 耗时 {time.perf_counter()-t0:.3f}s")
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"g{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":False})
c.assign([TopicPartition(TEST,i) for i in range(3)])
dist={}
for _ in range(15):
    ms=c.consume(num_messages=50,timeout=2)
    if not ms: break
    for m in ms:
        if not m.error(): dist[m.partition()]=dist.get(m.partition(),0)+1
print(f"  3 分区分布: {dist}  合计 {sum(dist.values())}")
c.close()
for t,f in a.delete_topics([TEST]).items(): f.result()
print(f"  清理 {TEST} ✓")

banner("分层测试策略（实测结论）")
print("  层1 Fake   : 业务逻辑/序列化/错误分支   毫秒级  每次 commit 跑")
print("  层2 真集群 : 分区语义/端到端/再均衡      秒级    提测前或 CI 定时跑")
print("  ⚠ Fake 必须与真实 API 同宽容度，否则测试假绿（本次实证）")
PYEOF
