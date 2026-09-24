"""课 3：消费组与位移查询 v2 —— 修正 confluent 2.15 的真实用法。

上一版踩坑（本课素材）：
  1. describe_consumer_groups 返回 dict，不是 Future（调 .result() → AttributeError）
  2. list_consumer_group_offsets 在 2.15 要传 ConsumerGroupTopicPartitions 对象列表，
     传字符串 → TypeError: Expected list of 'ConsumerGroupTopicPartitions'

这版按真实签名写。
"""
import socket
import time

from confluent_kafka import Consumer, TopicPartition
from confluent_kafka.admin import AdminClient as CfAdmin

try:
    from confluent_kafka.admin import ConsumerGroupTopicPartitions
    print("✓ ConsumerGroupTopicPartitions 可导入（2.15 新签名）")
except ImportError:
    from confluent_kafka import ConsumerGroupTopicPartitions
    print("✓ ConsumerGroupTopicPartitions 从顶层导入")

HOSTS = ["kafka-1", "kafka-2", "kafka-3"]
BS_LIST = []
for h in HOSTS:
    try:
        ip = socket.gethostbyname(h)
        s = socket.socket()
        s.settimeout(3)
        s.connect((ip, 9092))
        BS_LIST.append(f"{h}:9092")
        s.close()
    except OSError:
        pass
BS = ",".join(BS_LIST)
TOPIC = "l3-group-demo2"
GROUP = "l3-demo-group2"

# ============ 造数据 ============
from kafka import KafkaAdminClient
from kafka.admin import NewTopic
from kafka import KafkaConsumer, KafkaProducer

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r = admin.create_topics([NewTopic(TOPIC, num_partitions=2, replication_factor=1)])
    for it in r.get("topics", []):
        print(f"create: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:80]}")
time.sleep(1)

N = 10
p = KafkaProducer(bootstrap_servers=BS)
for i in range(N):
    p.send(TOPIC, f"msg-{i}".encode(), partition=i % 2)
p.flush()
print(f"发送 {N} 条")

c = KafkaConsumer(TOPIC, bootstrap_servers=BS, group_id=GROUP,
                  auto_offset_reset="earliest", enable_auto_commit=True,
                  consumer_timeout_ms=5000)
consumed = 0
for msg in c:
    consumed += 1
    if consumed >= 6:
        break
c.close()
print(f"消费 {consumed} 条（留 {N-consumed} 条 lag）")
time.sleep(2)

# ============ confluent 查询 ============
print("\n" + "=" * 70)
print("confluent 查消费组")
print("=" * 70)
cf = CfAdmin({"bootstrap.servers": BS})

# 1. 组列表
try:
    res = cf.list_consumer_groups().result()
    groups = getattr(res, "valid", [])
    print(f"  组数 = {len(groups)}")
    for g in groups:
        print(f"    - {g.group_id}  state={getattr(g,'state',None)}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:150]}")

# 2. 组详情（返回 dict，不调 result）
print(f"\n  --- describe_consumer_groups ---")
try:
    res = cf.describe_consumer_groups([GROUP])
    print(f"    返回 {type(res).__name__}（注意：不是 Future）")
    if isinstance(res, dict):
        for gid, g in res.items():
            g = g.result() if hasattr(g, "result") else g
            print(f"    group={gid}")
            print(f"      state    = {getattr(g,'state',None)}")
            print(f"      protocol = {getattr(g,'protocol',None)}")
            mems = getattr(g, "members", None) or []
            print(f"      members  = {len(mems)}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:200]}")

# 3. 位移（2.15 新签名：ConsumerGroupTopicPartitions）
print(f"\n  --- list_consumer_group_offsets（2.15 新签名）---")
committed = {}
try:
    cg = ConsumerGroupTopicPartitions(GROUP, [TopicPartition(TOPIC, 0),
                                              TopicPartition(TOPIC, 1)])
    res = cf.list_consumer_group_offsets([cg])
    print(f"    返回 {type(res).__name__}")
    for gid, fut in (res.items() if isinstance(res, dict) else []):
        r = fut.result() if hasattr(fut, "result") else fut
        tps = getattr(r, "topic_partitions", None) or []
        print(f"    group={gid}  分区数={len(tps)}")
        for tp in tps:
            print(f"      {tp.topic}-{tp.partition}: offset={tp.offset}")
            committed[tp.partition] = tp.offset
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:250]}")

# 4. lag
print(f"\n  --- lag 计算 ---")
try:
    probe = Consumer({"bootstrap.servers": BS, "group.id": "l3-lag-probe2",
                      "auto.offset.reset": "latest"})
    ends = {}
    for pid in (0, 1):
        lo, hi = probe.get_watermark_offsets(TopicPartition(TOPIC, pid))
        ends[pid] = hi
    probe.close()
    print(f"    {'分区':<8}{'committed':<14}{'log-end':<12}{'lag'}")
    total = 0
    for pid in sorted(ends):
        cm = committed.get(pid)
        le = ends[pid]
        if cm is None or cm < 0:
            lag = "未提交"
        else:
            lag = le - cm
            total += lag
        print(f"    {pid:<8}{str(cm):<14}{le:<12}{lag}")
    print(f"    总 lag = {total}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:200]}")

# ============ 清理 ============
print("\n" + "=" * 70)
try:
    r = admin.delete_topics([TOPIC])
    for it in r.get("topics", []):
        print(f"delete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:80]}")
admin.close()
