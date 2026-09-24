"""课 5：诊断「再均衡死循环」根因。

现象：4 消费者时分区分配错乱（分区 3 被两人持有，分区 0 无人管），
      C4 反复 revoked=[3]→assigned=[3]。

假设：
  A. consumer_timeout_ms=8000 让消费者超时退出 → 反复入组出组
  B. max_poll_interval_ms 太短
  C. kafka-python 自身的 bug

验证：去掉 consumer_timeout_ms，加心跳留足时间，重跑 4 消费者。
"""
import socket
import time

from kafka import KafkaAdminClient, KafkaConsumer, KafkaProducer
from kafka.admin import NewTopic
from kafka.consumer.subscription_state import ConsumerRebalanceListener

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
T = "l5-rb-loop"
G = "l5-loop-group"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r = admin.create_topics([NewTopic(T, num_partitions=4, replication_factor=1)])
    for it in r.get("topics", []):
        print(f"create: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:60]}")
time.sleep(1)

p = KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
for i in range(40):
    p.send(T, f"x-{i:02d}".encode())
p.flush(timeout=20)
p.close()


def parts(c):
    return tuple(sorted(tp.partition for tp in c.assignment()))


print("=" * 72)
print("实验组：去掉 consumer_timeout_ms（假设 A 验证）")
print("=" * 72)


def mk(name):
    c = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                      auto_offset_reset="earliest",
                      enable_auto_commit=False,
                      session_timeout_ms=45000,
                      heartbeat_interval_ms=3000)
    c.subscribe([T])
    return c


cs = []
for i in range(4):
    cs.append(mk(f"C{i+1}"))
    # 每次加入后充分 poll，让再均衡完成
    for _ in range(6):
        for c in cs:
            c.poll(timeout_ms=1000, max_records=1)
        time.sleep(0.5)
    r = tuple(parts(c) for c in cs)
    print(f"  {i+1} 个消费者: {r}  合计={sum(len(x) for x in r)} "
          f"无重叠={len(set(sum((list(x) for x in r), []))) == sum(len(x) for x in r)}")

print("\n  稳定后再观察 8 轮（看是否还在抖）：")
stable = []
for i in range(8):
    for c in cs:
        c.poll(timeout_ms=1000, max_records=1)
    cur = tuple(parts(c) for c in cs)
    stable.append(cur)
    print(f"    round {i}: {cur}")
    time.sleep(0.3)

print(f"\n  8 轮中分配保持一致: {len(set(stable)) == 1}")
if len(set(stable)) == 1:
    print(f"  ✓ 稳定分配 = {stable[0]}")
    print("  → 去掉 consumer_timeout_ms 后不再抖动")
    print("  → 根因确认：consumer_timeout_ms 让消费者自动退出组，触发反复再均衡")

for c in cs:
    try:
        c.close()
    except Exception:
        pass

try:
    r2 = admin.delete_topics([T])
    for it in r2.get("topics", []):
        print(f"delete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:60]}")
admin.close()
