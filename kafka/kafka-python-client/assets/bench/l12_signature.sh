#!/bin/bash
# confluent 的 produce 是 C 扩展，inspect 拿不到签名 -> 改用行为验证
# 判据：哪个关键字能让回调真的被调用
timeout 60 docker exec -i l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e 'from ._compat'
import json, time
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient, NewTopic
BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
print("="*74); print("Producer.produce 回调参数名：行为验证"); print("="*74)
a=AdminClient({"bootstrap.servers":BROKERS})
TEST=f"l12-sig-{int(time.time())%100000}"
for t,f in a.create_topics([NewTopic(TEST,num_partitions=1,replication_factor=1)]).items(): f.result()

def try_send(kwname,n=20):
    p=Producer({"bootstrap.servers":BROKERS})
    hit={"ok":0,"fail":0}; err=None
    def cb(e,msg):
        if e: hit["fail"]+=1
        else: hit["ok"]+=1
    try:
        for i in range(n):
            kw={kwname:cb}
            p.produce(TEST,json.dumps({"i":i}).encode(),**kw)
        p.flush(10)
    except TypeError as e: err=f"TypeError: {e}"
    except Exception as e: err=f"{type(e).__name__}: {e}"
    print(f"  produce(..., {kwname}=cb)  -> ok={hit['ok']:<4} fail={hit['fail']:<4} {err or ''}")
    return hit["ok"]

o=try_send("on_delivery")
c=try_send("callback")
for t,f in a.delete_topics([TEST]).items(): f.result()
print(f"\n  清理 {TEST} ✓")
print(f"\n{'─'*74}")
print(f"  on_delivery 触发回调: {o} 次")
print(f"  callback    触发回调: {c} 次")
print(f"\n  判定：{'on_delivery 是正确参数名' if o>0 and c==0 else ('callback 也对' if c>0 and o>0 else '仅 callback')}")
print(f"\n  ⚠ 我的 FakeProducer 用 on_delivery 收，业务代码却用 callback= 传")
print(f"    -> callback 落进 **kw 被静默吞掉，回调从不执行，测试假绿")
PYEOF
