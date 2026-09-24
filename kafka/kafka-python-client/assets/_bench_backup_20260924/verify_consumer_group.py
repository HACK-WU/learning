"""课 3：消费组与位移查询 —— 先造数据，再用 confluent 查。

kafka-python 没有消费组管理 API（实测 AttributeError），
所以这一块必须 confluent。本脚本：
  1. 用 kafka-python 建 topic + 发消息 + 消费（造出真实的组与位移）
  2. 用 confluent 查组列表、组成员、位移、lag
"""
import socket
import time

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

TOPIC = "l3-group-demo"
GROUP = "l3-demo-group"

print(f"bootstrap = {BS}")
print(f"topic={TOPIC}  group={GROUP}\n")

# ============ 1. 造数据 ============
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
print(f"发送 {N} 条（partition 0/1 各 {N//2} 条）")

# 消费掉一部分，留出 lag
c = KafkaConsumer(TOPIC, bootstrap_servers=BS, group_id=GROUP,
                  auto_offset_reset="earliest",
                  enable_auto_commit=True,
                  consumer_timeout_ms=5000)
consumed = 0
for msg in c:
    consumed += 1
    if consumed >= 6:      # 只消费 6 条，留 4 条 lag
        break
c.close()
print(f"消费 {consumed} 条后关闭（留 {N - consumed} 条 lag）")
time.sleep(2)

# ============ 2. kafka-python 尝试查组（预期失败） ============
print("\n" + "=" * 70)
print("2. kafka-python 查消费组（预期 AttributeError）")
print("=" * 70)
for api in ["list_consumer_groups", "list_consumer_group_offsets",
            "describe_consumer_groups"]:
    try:
        getattr(admin, api)()
        print(f"  {api:<32} ✓ 可用")
    except AttributeError:
        print(f"  {api:<32} ✗ AttributeError（没有这个 API）")
    except Exception as e:
        print(f"  {api:<32} ? {type(e).__name__}: {str(e)[:60]}")

# ============ 3. confluent 查组 ============
print("\n" + "=" * 70)
print("3. confluent-kafka 查消费组")
print("=" * 70)
from confluent_kafka import Consumer, TopicPartition
from confluent_kafka.admin import AdminClient as CfAdmin

cf = CfAdmin({"bootstrap.servers": BS})

# 3.1 列组
try:
    fut = cf.list_consumer_groups()
    res = fut.result()
    print(f"  list_consumer_groups → {type(res).__name__}")
    groups = res.valid if hasattr(res, "valid") else []
    print(f"  有效组数 = {len(groups)}")
    for g in groups:
        gid = getattr(g, "group_id", g)
        print(f"    - {gid}  (is_simple={getattr(g,'is_simple_consumer_group',None)}, "
              f"state={getattr(g,'state',None)})")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:150]}")

# 3.2 查组成员/详情
print(f"\n  --- describe_consumer_groups([{GROUP}]) ---")
try:
    fut = cf.describe_consumer_groups([GROUP])
    res = fut.result()
    for gid, g in res.items() if isinstance(res, dict) else []:
        print(f"    group={gid}")
        print(f"      state     = {getattr(g,'state',None)}")
        print(f"      protocol  = {getattr(g,'protocol',None)}")
        members = getattr(g, "members", None) or []
        print(f"      members   = {len(members)}")
        for m in members:
            print(f"        member_id={getattr(m,'member_id',None)} "
                  f"client={getattr(m,'client_id',None)}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:200]}")

# 3.3 查位移 + lag
print(f"\n  --- list_consumer_group_offsets([{GROUP}]) ---")
try:
    fut = cf.list_consumer_group_offsets([GROUP])
    res = fut.result()
    print(f"    返回 {type(res).__name__}")
    parts = res.get("partitions", []) if isinstance(res, dict) else []
    if not parts:
        print(f"    原始: {str(res)[:300]}")
    for tp in parts if isinstance(parts, list) else []:
        print(f"      {tp.topic}-{tp.partition}: offset={tp.offset} "
              f"metadata={getattr(tp,'metadata',None)}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:200]}")

# 3.4 算 lag：committed vs 最新 offset
print(f"\n  --- 计算 lag（committed vs log-end）---")
try:
    probe = Consumer({"bootstrap.servers": BS, "group.id": "l3-lag-probe",
                      "auto.offset.reset": "latest"})
    meta = probe.list_topics(TOPIC)
    ends = {}
    for tp in meta.topics[TOPIC].partitions.values():
        lo, hi = probe.get_watermark_offsets(
            TopicPartition(TOPIC, tp.id))
        ends[tp.id] = hi
    probe.close()
    print(f"    log-end offsets: {ends}")

    fut = cf.list_consumer_group_offsets([GROUP])
    res = fut.result()
    committed = {}
    if isinstance(res, dict):
        for tp in res.get("partitions", []):
            committed[tp.partition] = tp.offset
    print(f"    committed      : {committed}")
    print(f"    {'分区':<6}{'committed':<12}{'log-end':<10}{'lag'}")
    total = 0
    for pid in sorted(ends):
        cm = committed.get(pid)
        le = ends[pid]
        lag = (le - cm) if cm is not None and cm >= 0 else "（未提交）"
        if isinstance(lag, int):
            total += lag
        print(f"    {pid:<6}{str(cm):<12}{le:<10}{lag}")
    print(f"    总 lag = {total}")
except Exception as e:
    print(f"  失败: {type(e).__name__}: {str(e)[:200]}")

# ============ 4. 清理 ============
print("\n" + "=" * 70)
try:
    r = admin.delete_topics([TOPIC])
    for it in r.get("topics", []):
        print(f"delete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:80]}")
admin.close()
