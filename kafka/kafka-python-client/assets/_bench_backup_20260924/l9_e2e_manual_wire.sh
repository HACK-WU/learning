#!/bin/bash
# 课 9 实验④：端到端 —— 手工 Avro wire format 跑通生产消费（无 SR）
#
# 验证：kafka-python 用"手工拼 magic byte + schema id"能否跑通全链路
# 这是理解 Schema Registry 价值的前置：先知道手工怎么做，才知道 SR 省了什么
set -u
cat > /tmp/e2e.py <<'PYEOF'
import struct, io, json, sys
import fastavro
from kafka import KafkaProducer, KafkaConsumer
from kafka.admin import KafkaAdminClient, NewTopic

BOOT = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
TOPIC = "l9-orders-e2e"

# ---------- 一个最小的"手工 schema 仓库"（内存版，模拟 SR 的 id->schema 映射）----------
V1 = {"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"}]}
V2 = {"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"currency","type":"string","default":"CNY"}]}
SCHEMA_STORE = {1: V1, 2: V2}        # 真实 SR 里存在 _schemas topic
P_MAP = {k: fastavro.parse_schema(v) for k, v in SCHEMA_STORE.items()}

def encode(schema_id, rec):
    buf = io.BytesIO()
    fastavro.schemaless_writer(buf, P_MAP[schema_id], rec)
    return b"\x00" + struct.pack(">I", schema_id) + buf.getvalue()

def decode(wire):
    magic = wire[0]
    if magic != 0:
        raise ValueError(f"bad magic byte: {magic}")
    sid = struct.unpack(">I", wire[1:5])[0]
    if sid not in SCHEMA_STORE:
        raise KeyError(f"unknown schema id {sid}")
    return sid, fastavro.schemaless_reader(io.BytesIO(wire[5:]), P_MAP[sid])

# ---------- 建 topic ----------
try:
    adm = KafkaAdminClient(bootstrap_servers=BOOT, client_id="l9")
    try: adm.delete_topics([TOPIC])
    except Exception: pass
    import time; time.sleep(2)
    adm.create_topics([NewTopic(TOPIC, num_partitions=3, replication_factor=3)])
    adm.close(); time.sleep(2)
    print(f"✓ topic {TOPIC} 已建")
except Exception as e:
    print(f"? 建 topic: {type(e).__name__}: {str(e)[:80]}")

# ---------- 生产：v1 写 5 条 + v2 写 5 条（模拟 schema 演进后的混合写入）----------
prod = KafkaProducer(bootstrap_servers=BOOT, acks="all", linger_ms=0)
sent = []
for i in range(5):
    prod.send(TOPIC, value=encode(1, {"order_id":f"V1-{i}","amount":10.0+i}))
    sent.append(("v1", f"V1-{i}"))
for i in range(5):
    prod.send(TOPIC, value=encode(2, {"order_id":f"V2-{i}","amount":20.0+i,"currency":"USD"}))
    sent.append(("v2", f"V2-{i}"))
prod.flush()
print(f"✓ 生产 10 条（v1 五条 + v2 五条，同一 topic 混合）")
sample = encode(1, {"order_id":"V1-0","amount":10.0})
print(f"  v1 单条 wire: {len(sample)} 字节 -> {sample.hex()}")
print(f"  拆解: magic=00  schema_id={struct.unpack('>I', sample[1:5])[0]}  payload={len(sample)-5}字节")

# ---------- 消费：按消息自带的 schema id 自动选 schema ----------
cons = KafkaConsumer(TOPIC, bootstrap_servers=BOOT, auto_offset_reset="earliest",
                     group_id="l9-e2e-g", consumer_timeout_ms=15000,
                     enable_auto_commit=False)
got = []
for msg in cons:
    sid, rec = decode(msg.value)
    got.append((f"v{sid}", rec))
cons.close()

print(f"\n✓ 消费到 {len(got)} 条，逐条按自带 schema id 解码：")
for ver, rec in got[:10]:
    print(f"    {ver}  {rec}")

# ---------- 验证点 ----------
print("\n" + "=" * 70)
print("验证结论")
print("=" * 70)
ok_cnt = len(got) == 10
v1_recs = [r for v, r in got if v == "v1"]
v2_recs = [r for v, r in got if v == "v2"]
print(f"1. 条数正确: {len(got)}/10  -> {'✓' if ok_cnt else '✗'}")
print(f"2. v1 消息({len(v1_recs)}条) 被 v1 schema 解出，无 currency 字段")
print(f"   v2 消息({len(v2_recs)}条) 被 v2 schema 解出，有 currency 字段")
mixed = len(v1_recs) > 0 and len(v2_recs) > 0
print(f"3. 同一 topic 内 v1/v2 混合共存且各自正确: {'✓' if mixed else '✗'}")
print(f"   -> 这正是 Avro 的核心价值：新旧版本消息可以躺在一个 topic 里")
print("\n4. 但注意【手工方案的软肋】：")
print(f"   · SCHEMA_STORE 是我这个进程的内存字典，重启就没了")
print(f"   · 换个消费者要重新实现一遍 encode/decode，容易写歪")
print(f"   · 注册新 schema 时【没有任何校验】—— 我可以直接塞个不兼容的 V3 进去")
print(f"   · 生产消费者多了以后，id 分配会冲突（谁来发号？）")
print("=" * 70)
PYEOF
docker run --rm --network bench_kafka-net \
  -v /tmp/e2e.py:/e.py kafka-pybench:3.12 /app/.venv/bin/python /e.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' | head -40
