"""课 2：版本兼容矩阵 —— 客户端库版本 vs broker 版本。

实测：
  1. broker 版本（从集群拿）
  2. 各客户端库版本 + 其 librdkafka 版本
  3. 实际连通性（能否正常收发）
"""
import socket
import time

from kafka import KafkaAdminClient
from kafka.admin import NewTopic

HOSTS = ["kafka-1", "kafka-2", "kafka-3"]


def build_bs():
    ok = []
    for h in HOSTS:
        try:
            ip = socket.gethostbyname(h)
            s = socket.socket()
            s.settimeout(3)
            s.connect((ip, 9092))
            ok.append(f"{h}:9092")
            s.close()
        except OSError:
            pass
    return ",".join(ok)


BS = build_bs()
TOPIC = "l2-compat-check"
print(f"bootstrap = {BS}\n")

# ---------- 1. broker 版本 ----------
print("=" * 70)
print("1. Broker 版本（从集群实测）")
print("=" * 70)
admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=10000)
try:
    # ApiVersions 是拿 broker 版本最可靠的方式
    from kafka.protocol.admin import ApiVersionsRequest
    from kafka.protocol.api import Request, Response

    fut = admin._send_request(1 if False else 0, ApiVersionsRequest[0]())
    print("  （换用 describe_cluster 更简单）")
except Exception:
    pass

try:
    meta = admin.describe_cluster()
    print(f"  cluster_id  = {meta.get('cluster_id')}")
    print(f"  brokers     = {len(meta.get('brokers', []))} 个")
    for b in meta.get("brokers", []):
        print(f"    broker {b.get('broker_id')}: {b.get('host')}:{b.get('port')}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {e}")

# 用 _client 拿 api_versions
try:
    cl = admin._client
    versions = cl.cluster  # 可能有 broker 元数据
    print("\n  尝试 least_loaded_node 探版本:")
    node = cl.least_loaded_node()
    print(f"    least_loaded_node = {node}")
except Exception as e:
    print(f"    {type(e).__name__}: {str(e)[:60]}")

# ---------- 2. 客户端版本 ----------
print("\n" + "=" * 70)
print("2. 客户端库版本")
print("=" * 70)
import kafka
print(f"  kafka-python     : {kafka.__version__}")

import confluent_kafka
print(f"  confluent-kafka  : {confluent_kafka.version()}")
print(f"    librdkafka     : {confluent_kafka.libversion()}")

import aiokafka
print(f"  aiokafka         : {aiokafka.__version__}")

# ---------- 3. 三库实际连通性 ----------
print("\n" + "=" * 70)
print("3. 三库对同一集群的实际连通性")
print("=" * 70)

# 建 topic
try:
    fs = admin.create_topics([NewTopic(TOPIC, num_partitions=1, replication_factor=1)])
    for t, f in fs.items():
        f.result()
    time.sleep(1)
except Exception as e:
    print(f"  建 topic: {type(e).__name__}: {str(e)[:60]}")

# kafka-python
print("\n  --- kafka-python ---")
try:
    from kafka import KafkaConsumer, KafkaProducer
    p = KafkaProducer(bootstrap_servers=BS)
    f = p.send(TOPIC, b"kp")
    md = f.get(timeout=10)
    print(f"    ✓ 发送成功 p{md.partition}@{md.offset}")
    p.close()
except Exception as e:
    print(f"    ✗ {type(e).__name__}: {str(e)[:80]}")

# confluent
print("\n  --- confluent-kafka ---")
try:
    from confluent_kafka import Producer
    cp = Producer({"bootstrap.servers": BS})
    ok = {"done": False}

    def cb(err, msg):
        if err:
            print(f"    ✗ 投递失败: {err}")
        else:
            print(f"    ✓ 投递成功 p{msg.partition()}@{msg.offset()}")
        ok["done"] = True

    cp.produce(TOPIC, b"cf", callback=cb)
    cp.flush()
except Exception as e:
    print(f"    ✗ {type(e).__name__}: {str(e)[:80]}")

# aiokafka
print("\n  --- aiokafka ---")
import asyncio
from aiokafka import AIOKafkaProducer


async def ak_send():
    p = AIOKafkaProducer(bootstrap_servers=BS)
    await p.start()
    try:
        md = await p.send_and_wait(TOPIC, b"ak")
        print(f"    ✓ 发送成功 p{md.partition}@{md.offset}")
    finally:
        await p.stop()


try:
    asyncio.run(ak_send())
except Exception as e:
    print(f"    ✗ {type(e).__name__}: {str(e)[:80]}")

# ---------- 清理 ----------
print("\n" + "=" * 70)
# 注意：kafka-python 3.0.11 的 create/delete_topics 返回
#   {'topics': [{'name':..., 'error_code':...}, ...}]
# 不是 {topic: Future}。老写法 for t,f in fs.items(): f.result() 会 AttributeError
try:
    fs = admin.delete_topics([TOPIC])
    if isinstance(fs, dict) and "topics" in fs:
        for item in fs["topics"]:
            ec = item.get("error_code")
            nm = item.get("name")
            print(f"  {nm}: error_code={ec} {'✓' if ec == 0 else '✗'}")
        print(f"已清理 {TOPIC}")
    elif isinstance(fs, dict):
        for t, f in fs.items():
            f.result()
        print(f"已清理 {TOPIC}")
    else:
        print(f"  delete_topics 返回 {type(fs).__name__}，等待生效")
        import time as _t
        _t.sleep(2)
        print(f"已请求删除 {TOPIC}")
except Exception as e:
    print(f"清理: {type(e).__name__}: {str(e)[:60]}")
admin.close()
