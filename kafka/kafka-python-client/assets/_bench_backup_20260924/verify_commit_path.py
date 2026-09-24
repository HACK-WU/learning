"""课 5：位移提交路径实测 —— at-least-once 为什么会重复。

源码已知：
  - position 存在消费端内存（subscription_state）
  - enable_auto_commit=True, auto_commit_interval_ms=5000
  - commit 由 coordinator 异步批量提交

本节要证明的因果链：
  自动提交按「时间」触发，不是按「处理完成」触发
  => 处理到一半崩溃 => 已消费但未提交的位移丢失 => 重放 => 重复
"""
import socket
import time

from kafka import KafkaAdminClient, KafkaConsumer, KafkaProducer
from kafka.admin import NewTopic

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
T = "l5-commit-path"
G = "l5-commit-group"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r = admin.create_topics([NewTopic(T, num_partitions=1, replication_factor=1)])
    for it in r.get("topics", []):
        print(f"create: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:80]}")
time.sleep(1)

# 发 20 条
p = KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
for i in range(20):
    p.send(T, f"msg-{i:02d}".encode())
p.flush(timeout=20)
p.close()
print(f"已发送 20 条到 {T}")

print("\n" + "=" * 72)
print("1. 消费 10 条但【不提交】—— 看 committed 停在哪")
print("=" * 72)
c = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                  auto_offset_reset="earliest",
                  enable_auto_commit=False,          # 手动模式，看得清
                  max_poll_records=5,
                  consumer_timeout_ms=8000)
got = []
for msg in c:
    got.append(msg.value.decode())
    if len(got) >= 10:
        break
print(f"  消费到 {len(got)} 条: {got[:3]} ... {got[-2:]}")
from kafka.structs import TopicPartition
tp = TopicPartition(T, 0)
print(f"  position（消费端内存）  = {c.position(tp)}")
print(f"  committed（Broker 记录）= {c.committed(tp)}")
print(f"  → 消费了 10 条，但 Broker 完全不知道（committed 仍为 None/0）")
c.close()

print("\n" + "=" * 72)
print("2. 手动 commit 后，committed 才移动")
print("=" * 72)
c = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                  auto_offset_reset="earliest",
                  enable_auto_commit=False,
                  max_poll_records=5, consumer_timeout_ms=8000)
n = 0
for msg in c:
    n += 1
    if n >= 10:
        break
print(f"  又消费 {n} 条（重放！说明上一步没提交）")
c.commit()                                   # ← 手动提交
print(f"  commit() 之后 committed = {c.committed(tp)}")
c.close()

print("\n" + "=" * 72)
print("3. 自动提交：按时间触发，与「处理完成」无关")
print("=" * 72)
c = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                  auto_offset_reset="earliest",
                  enable_auto_commit=True,
                  auto_commit_interval_ms=5000,     # 默认 5 秒
                  max_poll_records=5, consumer_timeout_ms=8000)
for msg in c:
    pass
print(f"  自动提交模式消费完，committed = {c.committed(tp)}")
print("""  → 自动提交的时机由 auto_commit_interval_ms 决定，
     在 poll() 里顺带触发，跟你的业务是否处理完【没有任何关系】""")
c.close()

print("\n" + "=" * 72)
print("4. 关键对比：commit 之前崩溃会怎样")
print("=" * 72)
print("""  时间线：
    t0  poll() 拿到 msg 0~9
    t1  业务处理完 msg 0~4
    t2  【进程崩溃】
        ├─ position（内存）= 10   ← 随进程一起没了
        └─ committed（Broker）= 0 ← 持久化，还在
    t3  重启 → 从 committed=0 开始 → msg 0~9 全部重放

  这就是 at-least-once 的重复来源：
  消费进度存在两个地方，只有 committed 能活过崩溃。
""")

try:
    r = admin.delete_topics([T])
    for it in r.get("topics", []):
        print(f"delete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:80]}")
admin.close()
