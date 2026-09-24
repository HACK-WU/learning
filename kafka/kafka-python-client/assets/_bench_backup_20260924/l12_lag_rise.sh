#!/bin/bash
# 带 finally 清理版（避免异常时残留 topic）——改写 l12_lag_rise.sh 尾部
timeout 120 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import time, json
from confluent_kafka import Producer, Consumer
from confluent_kafka.admin import AdminClient, NewTopic
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
a=AdminClient({"bootstrap.servers":BROKERS})
T=f"l12-rise-{int(time.time())%100000}"
for t,f in a.create_topics([NewTopic(T,num_partitions=2,replication_factor=1)]).items(): f.result()
print("="*74); print("复审补充：lag 能否上升（gauge 双向性实测）"); print("="*74)
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"g{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":True,
            "auto.commit.interval.ms":300})
try:
    c.subscribe([T])
    for _ in range(50):
        c.consume(num_messages=1,timeout=1)
        if c.assignment(): break
    print(f"  已分配分区: {[tp.partition for tp in c.assignment()]}")
    def lagof():
        tot=0
        for tp in c.assignment():
            try:
                lo,hi=c.get_watermark_offsets(tp,timeout=5)
                cm=c.committed([tp],timeout=5)[0].offset
                if hi<0: continue
                tot+=max(0,hi-(cm if cm and cm>=0 else 0))
            except Exception: pass
        return tot
    p=Producer({"bootstrap.servers":BROKERS,"linger.ms":0})
    seq=[]
    print(f"\n  阶段A · 只生产不消费（lag 应上升）")
    for i in range(5):
        for j in range(500): p.produce(T, json.dumps({"i":i*500+j}).encode())
        p.flush(10); seq.append(lagof()); print(f"    第{i+1}轮: lag = {seq[-1]}")
        time.sleep(0.3)
    rise = all(seq[i]<=seq[i+1] for i in range(len(seq)-1)) and seq[-1]>seq[0]
    print(f"  序列: {seq}   {'✓ 严格递增' if rise else '✗ 未上升'} (增量 {seq[-1]-seq[0]})")
    print(f"\n  阶段B · 开始消费（lag 应下降）")
    try: c.commit(asynchronous=False)
    except Exception as e: print(f"    (首次 commit 无位移，忽略: {type(e).__name__})")
    seq2=[]
    for i in range(5):
        c.consume(num_messages=400,timeout=3); c.commit(asynchronous=False)
        seq2.append(lagof()); print(f"    第{i+1}轮: lag = {seq2[-1]}"); time.sleep(0.3)
    fall = seq2[-1] < seq2[0]
    print(f"  序列: {seq2}   {'✓ 下降' if fall else '✗'}")
    print(f"\n{'─'*74}")
    print(f"  判定：lag 既上升({rise}) 又下降({fall}) -> 双向可变 = gauge 坐实")
finally:
    c.close()
    try:
        for t,f in a.delete_topics([T]).items(): f.result()
        print(f"  清理 {T} ✓")
    except Exception as e:
        print(f"  清理失败: {type(e).__name__}")
PYEOF
