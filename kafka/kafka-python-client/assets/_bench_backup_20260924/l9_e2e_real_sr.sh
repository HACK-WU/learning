#!/bin/bash
# 课 9 实验⑦（修正版）：真 SR + Kafka 端到端闭环
#
# 修正记录：首版消费到 0 条。诊断确认【消息确实在 topic 里】
#   （命令行消费者读到了 V2-0/V2-2/V1-0，_schemas topic 也存在）
#   问题在 Python 消费端：DeserializingConsumer 首次 rebalance 需要时间，
#   25 秒 deadline 里大部分耗在 join group + 分区分配上
# 修正：消费循环加长到 60 秒，并打印 rebalance 过程
set -u
cat > /tmp/e2e_sr2.py <<'PYEOF'
import json, time, sys
from confluent_kafka import SerializingProducer, DeserializingConsumer
from confluent_kafka.schema_registry import SchemaRegistryClient, Schema
from confluent_kafka.schema_registry.avro import AvroSerializer, AvroDeserializer

BOOT = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
SR_URL = "http://l9-sr:8081"
TOPIC = "l9-orders-sr2"

client = SchemaRegistryClient({"url": SR_URL})
SUBJ = f"{TOPIC}-value"
V1 = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"}]})
V2 = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"currency","type":"string","default":"CNY"}]})
id1 = client.register_schema(SUBJ, Schema(V1, "AVRO"))
id2 = client.register_schema(SUBJ, Schema(V2, "AVRO"))
print(f"✓ schema 注册: v1->id{id1}, v2->id{id2}")

# ⚠ 集群关了 auto.create.topics.enable（课 9 compose 里显式设的），
#   不显式建 topic 会报 UNKNOWN_TOPIC_OR_PART —— 首版漏了这步
from kafka.admin import KafkaAdminClient, NewTopic
adm = KafkaAdminClient(bootstrap_servers=BOOT, client_id="l9e2e2")
try: adm.delete_topics([TOPIC]); time.sleep(2)
except Exception: pass
adm.create_topics([NewTopic(TOPIC, num_partitions=3, replication_factor=3)])
adm.close(); time.sleep(3)
print(f"✓ topic {TOPIC} 已建（3 分区 / 3 副本）")

# ---------- 生产 ----------
def key_ser(k, ctx): return k.encode() if isinstance(k, str) else k
def key_deser(k, ctx): return k.decode() if isinstance(k, bytes) else k

p2 = SerializingProducer({"bootstrap.servers":BOOT,"key.serializer":key_ser,
                          "value.serializer":AvroSerializer(client, V2)})
for i in range(5):
    p2.produce(TOPIC, key=f"k{i}",
               value={"order_id":f"V2-{i}","amount":20.0+i,"currency":"USD"})
p2.flush()
print("✓ v2 serializer 生产 5 条")

p1 = SerializingProducer({"bootstrap.servers":BOOT,"key.serializer":key_ser,
                          "value.serializer":AvroSerializer(client, V1)})
for i in range(5):
    p1.produce(TOPIC, key=f"k{i}", value={"order_id":f"V1-{i}","amount":10.0+i})
p1.flush()
print("✓ v1 serializer 生产 5 条（模拟老生产者未升级）")

# ---------- 消费（加长超时，打印 rebalance）----------
events = []
def on_assign(c, ps):
    events.append(f"assign: {len(ps)} 个分区 {[p.partition for p in ps]}")

c = DeserializingConsumer({
    "bootstrap.servers": BOOT,
    "group.id": f"l9-sr2-g-{int(time.time())}",   # 新组，保证 from earliest
    "auto.offset.reset": "earliest",
    "key.deserializer": key_deser,
    "value.deserializer": AvroDeserializer(client, V2),
    "enable.auto.commit": False,
    "session.timeout.ms": 10000,
})
c.subscribe([TOPIC], on_assign=on_assign)

got = []
t0 = time.time()
deadline = t0 + 60
polls = 0
while len(got) < 10 and time.time() < deadline:
    m = c.poll(1.0); polls += 1
    if m is None: continue
    if m.error():
        print(f"  err: {m.error()}"); continue
    got.append(m.value())
    if len(got) == 1:
        events.append(f"首条消息耗时 {time.time()-t0:.1f}s（含 join group + 分配）")
c.close()

for e in events: print(f"  · {e}")
print(f"\n✓ 消费到 {len(got)}/10 条（poll {polls} 次，用时 {time.time()-t0:.1f}s）")
for r in got: print(f"    {r}")

print("\n" + "=" * 72)
print("端到端结论（真 SR）")
print("=" * 72)
v1_recs = [r for r in got if r and str(r.get("order_id","")).startswith("V1")]
v2_recs = [r for r in got if r and str(r.get("order_id","")).startswith("V2")]
print(f"1. 总条数: {len(got)}/10  {'✓' if len(got)==10 else '✗'}")
print(f"2. v1 消息 {len(v1_recs)} 条（老生产者写的，本身无 currency）")
if v1_recs: print(f"   -> 被 v2 schema 读出: {v1_recs[0]}")
print(f"3. v2 消息 {len(v2_recs)} 条")
if v2_recs: print(f"   -> {v2_recs[0]}")
print()
if v1_recs and "currency" in v1_recs[0]:
    print("→ backward 兼容兑现：v1 消息缺 currency，读时自动填 v2 的默认值 CNY")
    print("  老生产者不用改、不用停机，新消费者就能读全部数据")
print("=" * 72)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/e2e_sr2.py:/e.py \
  kafka-pybench:3.12 /app/.venv/bin/python /e.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' -e 'AuthlibDeprecation' -e 'from ._compat' \
  | head -45
