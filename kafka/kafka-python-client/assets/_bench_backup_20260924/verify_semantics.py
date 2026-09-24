"""课 6：三种确认语义的重复行为实证 + at-least-once 收口。

课 5 已证明：position（内存） vs committed（Broker）双轨 → 重复窗口。
本课补完：
  1. 三种语义在源码层面差在哪（acks 参数 → 谁确认）
  2. at-least-once 重复的【完整因果链】实测
  3. 幂等能消除哪一类重复、不能消除哪一类（关键边界）

核心区分（必须讲清）：
  - 幂等消除【producer 重试导致的重复】（同一会话内）
  - 幂等【不能】消除【consumer 提交滞后导致的重复】
  这是最容易混淆的地方。
"""
import socket
import time

from kafka import KafkaAdminClient, KafkaConsumer, KafkaProducer
from kafka.admin import NewTopic
from kafka.structs import TopicPartition

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
T = "l6-sem"
G = "l6-sem-g"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    admin.delete_topics([T]); time.sleep(1)
except Exception:
    pass
try:
    r = admin.create_topics([NewTopic(T, num_partitions=1,
                                      replication_factor=1)])
    print(f"create: error_code={r.get('topics',[{}])[0].get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:70]}")


def count_msgs():
    """用独立消费者数一遍 topic 里有多少条"""
    c = KafkaConsumer(T, bootstrap_servers=BS, group_id=f"{G}-cnt-{time.time()}",
                      auto_offset_reset="earliest", enable_auto_commit=False,
                      consumer_timeout_ms=6000)
    n = sum(1 for _ in c)
    c.close()
    return n


print("\n" + "=" * 74)
print("1. 三种语义：acks 决定「谁确认了才算成功」")
print("=" * 74)
print("""  acks=0   生产者发出即算成功（不等任何确认）  → 最多一次，会丢
  acks=1   leader 写入即算成功                → 较多一次，leader 挂了会丢
  acks=-1  所有 ISR 副本写入才算成功          → at-least-once 的基础""")

for tag, kw in [("acks=0", {"acks": 0}),
                ("acks=1", {"acks": 1}),
                ("acks=-1（默认）", {})]:
    p = KafkaProducer(bootstrap_servers=BS, max_block_ms=10000, **kw)
    a = p.config.get("acks")
    idem = p.config.get("enable_idempotence")
    print(f"  {tag:<16} → 实际 acks={a}, enable_idempotence={idem}")
    p.close()

print("\n" + "=" * 74)
print("2. at-least-once 重复的完整因果链（实测）")
print("=" * 74)
p = KafkaProducer(bootstrap_servers=BS, max_block_ms=10000, acks=-1)
for i in range(10):
    p.send(T, f"s-{i:02d}".encode())
p.flush(timeout=15)
p.close()
print(f"  生产 10 条，topic 实际 {count_msgs()} 条")

tp = TopicPartition(T, 0)

# 第一轮：消费但不提交
c = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                  auto_offset_reset="earliest", enable_auto_commit=False,
                  consumer_timeout_ms=6000)
got1 = []
for msg in c:
    got1.append(msg.value.decode())
    if len(got1) >= 10:
        break
print(f"  第 1 轮消费 {len(got1)} 条: {got1[:3]}...")
print(f"    position={c.position(tp)}  committed={c.committed(tp)}")
c.close()          # ← 模拟崩溃：没 commit

# 第二轮：重新消费
c2 = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                   auto_offset_reset="earliest", enable_auto_commit=False,
                   consumer_timeout_ms=6000)
got2 = []
for msg in c2:
    got2.append(msg.value.decode())
    if len(got2) >= 10:
        break
print(f"  第 2 轮消费 {len(got2)} 条: {got2[:3]}...")
print(f"    → 与第 1 轮完全相同: {got1 == got2}")
print(f"    【重复消费 {len(got2)} 条】")
c2.commit()
print(f"    commit 后 committed={c2.committed(tp)}")
c2.close()

print("\n" + "=" * 74)
print("3. 关键边界：幂等能消除【哪一类】重复？")
print("=" * 74)
print("""  ┌─ 重复类型 A：producer 重试导致的重复
  │   场景：send 成功但 ack 丢失 → producer 重试 → 同一条写两遍
  │   幂等能否消除：✅ 能（PID + seq 让 broker 识别并丢弃重复批次）
  │
  └─ 重复类型 B：consumer 提交滞后导致的重复
      场景：消费了但没 commit 就崩溃 → 重启后重放
      幂等能否消除：❌ 不能！
      原因：这是【两次不同的消费】，不是【同一次发送写两遍】
            broker 里只有 1 条消息，是消费者读了 2 次
      解法：消费端幂等（去重表 / 唯一键 / 事务 + read_committed）
""")

print("  实测说话：上面第 2 轮重复了 10 条，而 topic 里始终只有：")
print(f"    topic 实际条数 = {count_msgs()}（没有变成 20 条）")
print("    → 证明重复发生在【消费侧】，broker 侧无重复")

print("\n" + "=" * 74)
print("4. 消费端怎么防重（正解）")
print("=" * 74)
print("""  方案 1：业务幂等（最常用）
         用业务唯一键（订单号）先查去重表，存在则跳过

  方案 2：手动提交 + 处理完再提交（缩小窗口，不消除）
         for msg in consumer:
             process(msg)          # 先处理
             consumer.commit()     # 处理成功才提交
         ⚠️ 仍可能重复：commit 成功但进程在之后崩溃 → 见课 5 双轨模型

  方案 3：事务 + read_committed（Kafka 原生 EOS，课 8 讲）
         producer.begin_transaction() / send_offsets_to_transaction()
         consumer 配 isolation_level='read_committed'
""")

print("=" * 74)
print("5. isolation_level 默认值（课 8 预告）")
print("=" * 74)
from kafka import KafkaConsumer as KC
print(f"  isolation_level 默认 = {KC.DEFAULT_CONFIG.get('isolation_level')}")
print("  → 默认 read_uncommitted：会读到未提交/已中止事务的消息")

try:
    admin.delete_topics([T])
    print("\n已清理 topic")
except Exception as e:
    print(f"cleanup: {type(e).__name__}")
admin.close()
