"""课 2 实测：confluent / aiokafka 的「替代 API」真能跑通吗？

不只是列名字 —— 真连集群跑一遍，证明映射是对的。
同时验证：用错 API 时报错长什么样（学员排查时能认出来）。
"""
import socket
import time

HOSTS = ["kafka-1", "kafka-2", "kafka-3"]


def bs():
    ok = []
    for h in HOSTS:
        try:
            ip = socket.gethostbyname(h)
        except socket.gaierror:
            continue
        s = socket.socket()
        s.settimeout(3)
        try:
            s.connect((ip, 9092))
            ok.append(f"{h}:9092")
        except OSError:
            pass
        finally:
            s.close()
    return ",".join(ok)


BS = bs()
TOPIC = "l2-api-verify"
print(f"bootstrap = {BS}")

# ============ 1. confluent-kafka：produce（不是 send） ============
print("\n" + "=" * 70)
print("1. confluent-kafka：produce() 真能发")
print("=" * 70)
from confluent_kafka import Consumer as CfConsumer
from confluent_kafka import Producer as CfProducer
from confluent_kafka.admin import AdminClient, NewTopic

admin = AdminClient({"bootstrap.servers": BS})
try:
    fs = admin.create_topics([NewTopic(TOPIC, num_partitions=1, replication_factor=1)])
    for t, f in fs.items():
        f.result()
    print(f"  建 topic {TOPIC}")
except Exception as e:
    print(f"  建 topic（可能已存在）: {type(e).__name__}: {str(e)[:80]}")
time.sleep(1)


def on_delivery(err, msg):
    if err:
        print(f"  ✗ 投递失败: {err}")
    else:
        print(f"  ✓ 投递成功 p{msg.partition()}@{msg.offset()}")


cfp = CfProducer({"bootstrap.servers": BS})
cfp.produce(TOPIC, b"confluent-hello", callback=on_delivery)
cfp.flush()
print("  → confluent 用 produce()，没有 send()")

# ============ 2. confluent：commitSync 陷阱的报错样貌 ============
print("\n" + "=" * 70)
print("2. confluent：调 commitSync() 会怎样")
print("=" * 70)
cfc = CfConsumer({
    "bootstrap.servers": BS,
    "group.id": "l2-api-group",
    "auto.offset.reset": "earliest",
})
cfc.subscribe([TOPIC])
try:
    cfc.commitSync()
except AttributeError as e:
    print(f"  ✗ AttributeError: {e}")
    print("  → confluent 也没有 commitSync()，这是纯 Java 命名")
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:120]}")

# ============ 3. confluent：seek_to_beginning 的替代 ============
print("\n" + "=" * 70)
print("3. confluent：seek_to_beginning() 不存在，用 get_watermark_offsets 替代")
print("=" * 70)
msg = cfc.consume(num_messages=1, timeout=8)
if msg:
    m = msg[0]
    if m.error():
        print(f"  ✗ 消费错误: {m.error()}")
    else:
        print(f"  ✓ 收到 {m.value().decode()} (p{m.partition()}@{m.offset()})")
    tp = m  # 用消息本身定位

    # 真实替代写法
    from confluent_kafka import TopicPartition
    parts = cfc.assignment()
    print(f"  assignment: {parts}")
    if parts:
        lo, hi = cfc.get_watermark_offsets(parts[0])
        print(f"  get_watermark_offsets({parts[0].topic},{parts[0].partition}) → (low={lo}, high={hi})")
        print(f"  → 等同于 beginning_offsets/end_offsets 的组合")
        # seek 到开头
        cfc.seek(TopicPartition(parts[0].topic, parts[0].partition, lo))
        print(f"  ✓ seek(low={lo}) 成功 → 这就是 seek_to_beginning 的替代")
else:
    print("  未收到消息")

cfc.close()
cfp.close()

# ============ 4. aiokafka：start/stop + getone（不是 close/poll） ============
print("\n" + "=" * 70)
print("4. aiokafka：start()/stop() + getone()，没有 close()/poll()")
print("=" * 70)
import asyncio

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer


async def aiokafka_demo():
    p = AIOKafkaProducer(bootstrap_servers=BS)
    await p.start()
    try:
        md = await p.send_and_wait(TOPIC, b"aiokafka-hello")
        print(f"  ✓ 发送成功 p{md.partition}@{md.offset}")
    finally:
        await p.stop()

    c = AIOKafkaConsumer(TOPIC, bootstrap_servers=BS,
                         group_id="l2-async-group",
                         auto_offset_reset="earliest")
    await c.start()
    try:
        m = await c.getone()
        print(f"  ✓ getone 收到 {m.value.decode()} (p{m.partition}@{m.offset})")
        print("  → aiokafka 用 getone()/getmany()，没有 poll()")
    finally:
        await c.stop()
    print("  → aiokafka 用 start()/stop()，没有 close()")


asyncio.run(aiokafka_demo())

# ============ 5. 清理 ============
print("\n" + "=" * 70)
print("5. 清理")
print("=" * 70)
try:
    fs = admin.delete_topics([TOPIC])
    for t, f in fs.items():
        f.result()
    print(f"  已删除 {TOPIC}")
except Exception as e:
    print(f"  清理: {type(e).__name__}: {str(e)[:80]}")
