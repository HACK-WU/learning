"""课 5：诊断「新消费者拿到空分配」的根因。

现象：C2/C3 加入后 assignment 为空，C1 一直占 4 个分区。
假设 A：C1 构造时传 topic（隐式 subscribe，无 listener）→ 不响应 revoke
假设 B：只是 poll 次数不够，再均衡还没轮到
假设 C：所有消费者都用 group_id 但订阅方式不同导致协议不一致

验证方式：给【所有】消费者都加 listener，看是否收敛到均分。
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
T = "l5-rb-diag"
G = "l5-diag-group"

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
    p.send(T, f"d-{i:02d}".encode())
p.flush(timeout=20)
p.close()

LOG = []


class L(ConsumerRebalanceListener):
    def __init__(self, name):
        self.name = name

    def on_partitions_revoked(self, revoked):
        LOG.append(f"{self.name}.revoked={sorted(tp.partition for tp in revoked)}")

    def on_partitions_assigned(self, assigned):
        LOG.append(f"{self.name}.assigned={sorted(tp.partition for tp in assigned)}")


def mk(name):
    """关键差异：这次【所有】消费者都显式 subscribe + listener"""
    c = KafkaConsumer(bootstrap_servers=BS, group_id=G,
                      auto_offset_reset="earliest", enable_auto_commit=False,
                      consumer_timeout_ms=8000)
    c.subscribe([T], listener=L(name))
    return c


def parts(c):
    return tuple(sorted(tp.partition for tp in c.assignment()))


def settle(cs, rounds=20, ms=1200):
    prev = None
    for _ in range(rounds):
        for c in cs:
            c.poll(timeout_ms=ms, max_records=1)
        cur = tuple(parts(c) for c in cs)
        tot = sum(len(x) for x in cur)
        if tot == 4 and cur == prev and all(len(x) > 0 for x in cur):
            return cur, True
        prev = cur
        time.sleep(0.4)
    return prev, False


print("\n" + "=" * 72)
print("全部用 subscribe+listener，逐步加入")
print("=" * 72)
c1 = mk("C1")
c1.poll(timeout_ms=3000, max_records=1)
print(f"  1 个消费者: C1={parts(c1)}")

c2 = mk("C2")
r, ok = settle([c1, c2])
print(f"  2 个消费者: C1={r[0]} C2={r[1]}  收敛={ok}")

c3 = mk("C3")
r, ok = settle([c1, c2, c3], rounds=24)
print(f"  3 个消费者: C1={r[0]} C2={r[1]} C3={r[2]}  收敛={ok}")

c4 = mk("C4")
r, ok = settle([c1, c2, c3, c4], rounds=24)
print(f"  4 个消费者: {r}  收敛={ok}")

print("\n  监听器事件序列：")
for e in LOG:
    print(f"    {e}")

print("\n" + "=" * 72)
print("结论判定")
print("=" * 72)
if ok and all(len(x) == 1 for x in r):
    print("  ✓ 全部消费者都显式 subscribe+listener 时，4 分区均分给 4 个消费者")
    print("  → 上一版的空分配是因为 C1 未参与 revoke（构造传参 vs 显式 subscribe）")
else:
    print(f"  ? 未达理想均分，当前 {r}，需要继续排查")

for c in (c1, c2, c3, c4):
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
