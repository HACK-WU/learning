#!/bin/bash
# 课 12 探路：confluent-kafka stats 回调 + lag 采集能力摸底
# 铁律先行（mem_274a28_126d48b）：任何指标进告警前，先看实际值域 + 语义
set -u
cat > /tmp/l12_p1.py <<'PYEOF'
import json, time, threading
from confluent_kafka import Producer, Consumer, KafkaException

BROKERS="kafka-1:9092,kafka-2:9092,kafka-3:9092"
TOPIC="l11-async-bench"

def banner(t): print(f"\n{'─'*74}\n{t}\n{'─'*74}")

# ═══ 1. stats 回调能吐什么 ═══
banner("1. statistics.interval.ms 回调：字段总量与顶层结构")
got={"n":0,"doc":None}
def on_stats(json_str):
    got["n"]+=1
    if got["doc"] is None: got["doc"]=json.loads(json_str)

p=Producer({"bootstrap.servers":BROKERS,
            "statistics.interval.ms":1000,
            "stats_cb":on_stats})
p.produce(TOPIC,b"probe")
p.flush(10)
time.sleep(2.5)
p.flush(5)
print(f"  回调触发次数（2.5s，间隔1s）: {got['n']}")
if got["doc"]:
    d=got["doc"]
    print(f"  顶层字段数: {len(d)}")
    print(f"  顶层键: {sorted(d.keys())}")
    print(f"  JSON 总字节: {len(json.dumps(d))}")
    # 关键子集
    for k in ["brokers","topics","cgrp"]:
        if k in d:
            v=d[k]
            if isinstance(v,dict):
                print(f"\n  [{k}] {len(v)} 项")
                if k=="brokers":
                    b0=list(v.values())[0]
                    print(f"    单 broker 字段数: {len(b0)}")
                    print(f"    含: {[x for x in ['name','nodeid','state','outbuf_cnt','waitresp_cnt','rtt','tx','rx','txmsgs','rxmsgs'] if x in b0]}")
                if k=="cgrp":
                    print(f"    字段: {sorted(v.keys())[:20]}")
            else: print(f"    = {v}")

# ═══ 2. lag 怎么拿 ═══
banner("2. lag 采集：三种途径实测")
from confluent_kafka import TopicPartition
c=Consumer({"bootstrap.servers":BROKERS,"group.id":f"l12-probe-{int(time.time())%100000}",
            "auto.offset.reset":"earliest","enable.auto.commit":False})
# a) 已分配分区
parts=[TopicPartition(TOPIC,i) for i in range(4)]
lo_hi=c.get_watermark_offsets(parts[0],timeout=10)
print(f"  a) get_watermark_offsets -> (low,high) = {lo_hi}")
# b) committed
try:
    cm=c.committed(parts,timeout=10)
    print(f"  b) committed() -> {[(tp.partition,tp.offset) for tp in cm]}")
except Exception as e: print(f"  b) committed 失败: {type(e).__name__}: {e}")
# c) 消费后 position
c.assign(parts)
msgs=c.consume(num_messages=5,timeout=5)
pos=[c.position([p])[0] for p in parts[:1]]
print(f"  c) 消费 {len(msgs)} 条后 position -> {[(tp.partition,tp.offset) for tp in pos]}")
c.close()

# ═══ 3. lag 计算口径核验（关键：committed 为 -1001 时怎么办）═══
banner("3. lag 口径核验：未提交时 committed 返回值")
print("  上表若出现 offset=-1001，即 __PARTITION_EOF 语义，直接算 lag 会得天文数字")
print("  需显式处理：offset < 0 时视为 0（尚未提交任何位移）")
PYEOF
docker cp /tmp/l12_p1.py l11:/p1.py >/dev/null
docker exec l11 /app/.venv/bin/python /p1.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -45
