"""课 5：再均衡重测 —— 修正两处。

上版问题：
  1. C2 分配为 [] —— 再均衡未完成就读了 assignment（中间态）
  2. listener 必须继承 ConsumerRebalanceListener（不能鸭子类型）

这版：等再均衡真正收敛（轮询直到分区数稳定），listener 正确继承。
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
T = "l5-rebalance"
G = "l5-rb-group"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r = admin.create_topics([NewTopic(T, num_partitions=4, replication_factor=1)])
    for it in r.get("topics", []):
        print(f"create: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:80]}")
time.sleep(1)

p = KafkaProducer(bootstrap_servers=BS, max_block_ms=15000, acks=1)
for i in range(40):
    p.send(T, f"r-{i:02d}".encode())
p.flush(timeout=20)
p.close()
print("已发 40 条到 4 分区")


def parts(c):
    return sorted(tp.partition for tp in c.assignment())


def settle(cs, rounds=12, ms=1500):
    """反复 poll 直到所有消费者的分区分配稳定（再均衡收敛）"""
    prev = None
    for _ in range(rounds):
        for c in cs:
            c.poll(timeout_ms=ms, max_records=1)
        cur = tuple(tuple(parts(c)) for c in cs)
        tot = sum(len(x) for x in cur)
        if tot == 4 and cur == prev:
            return cur, True
        prev = cur
        time.sleep(0.5)
    return prev, False


print("\n" + "=" * 72)
print("1. 单消费者：独占 4 分区")
print("=" * 72)
c1 = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                   auto_offset_reset="earliest", enable_auto_commit=False,
                   consumer_timeout_ms=8000)
c1.poll(timeout_ms=3000, max_records=1)
print(f"  C1: {parts(c1)}")

print("\n" + "=" * 72)
print("2. 加入 C2，等再均衡收敛")
print("=" * 72)
events = []


class L(ConsumerRebalanceListener):          # ← 必须继承
    def on_partitions_revoked(self, revoked):
        events.append(("revoked", sorted(tp.partition for tp in revoked)))

    def on_partitions_assigned(self, assigned):
        events.append(("assigned", sorted(tp.partition for tp in assigned)))


c2 = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                   auto_offset_reset="earliest", enable_auto_commit=False,
                   consumer_timeout_ms=8000)
c2.subscribe([T], listener=L())
res, ok = settle([c1, c2])
print(f"  收敛={ok}  C1: {res[0]}  C2: {res[1]}")
print(f"  互不重叠: {not (set(res[0]) & set(res[1]))}，合计 {len(res[0])+len(res[1])} 分区")

print("\n" + "=" * 72)
print("3. 加入 C3（4 分区 3 消费者 → 必有一个拿 2 个）")
print("=" * 72)
c3 = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                   auto_offset_reset="earliest", enable_auto_commit=False,
                   consumer_timeout_ms=8000)
c3.subscribe([T], listener=L())
res3, ok3 = settle([c1, c2, c3], rounds=16)
print(f"  收敛={ok3}  C1: {res3[0]}  C2: {res3[1]}  C3: {res3[2]}")
allp = list(res3[0]) + list(res3[1]) + list(res3[2])
print(f"  合计 {len(allp)} 分区，无重叠: {len(set(allp)) == 4}")
print(f"  监听器捕获事件数: {len(events)}")
for e in events[-6:]:
    print(f"    {e[0]}: {e[1]}")

print("\n" + "=" * 72)
print("4. 关闭 C1 → 它的分区被回收重分")
print("=" * 72)
c1.close()
res4, ok4 = settle([c2, c3], rounds=16)
print(f"  收敛={ok4}  C2: {res4[0]}  C3: {res4[1]}")
print(f"  合计 {len(res4[0]) + len(res4[1])} 分区（应为 4）")

for c in (c2, c3):
    try:
        c.close()
    except Exception:
        pass

print("\n" + "=" * 72)
print("5. 心跳/poll 超时参数")
print("=" * 72)
from kafka import KafkaConsumer as KC
for k in ("session_timeout_ms", "heartbeat_interval_ms",
          "max_poll_interval_ms", "rebalance_timeout_ms"):
    print(f"  {k:<28} = {KC.DEFAULT_CONFIG.get(k)}")

try:
    r = admin.delete_topics([T])
    for it in r.get("topics", []):
        print(f"delete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:80]}")
admin.close()
