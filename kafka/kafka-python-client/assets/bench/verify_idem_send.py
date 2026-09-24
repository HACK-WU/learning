"""课 6：幂等三元组实测 —— 发送后拿真实 producer_id/epoch/sequence。

上一步发现 producer_id_and_epoch = (-1,-1)：因为【还没发消息】。
InitProducerId 是惰性的，首次发送才触发。

要验证：
  1. 发送后 producer_id / epoch 变成真实值（非 -1）
  2. base_sequence 从 0 开始
  3. 非幂等 producer 发送后仍是 -1
  4. 关键：幂等【只在单会话内有效】—— 重启 producer 后 PID 变化
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
T = "l6-idem"
G = "l6-idem-g"

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    admin.delete_topics([T])
    time.sleep(1)
except Exception:
    pass
try:
    r = admin.create_topics([NewTopic(T, num_partitions=1,
                                      replication_factor=1)])
    for it in r.get("topics", []):
        print(f"create: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:70]}")


def show(p, tag):
    tm = p._transaction_manager
    pae = getattr(tm, "producer_id_and_epoch", None)
    print(f"  [{tag}] producer_id_and_epoch = {pae}")
    return pae


print("\n" + "=" * 74)
print("1. 幂等 producer：发送【前】 vs 发送【后】")
print("=" * 74)
p1 = KafkaProducer(bootstrap_servers=BS, max_block_ms=10000)   # 默认幂等开
print(f"  enable_idempotence = {p1.config.get('enable_idempotence')}")
show(p1, "发送前")
f = p1.send(T, b"hello-idempotent")
f.get(timeout=15)
p1.flush(timeout=15)
show(p1, "发送后")
print("  → 首次发送才触发 InitProducerId（惰性初始化）")

# 再看 sequence
tm1 = p1._transaction_manager
for attr in ("_sequence_numbers", "sequence_number", "next_sequence"):
    v = getattr(tm1, attr, "【无】")
    if v != "【无】":
        print(f"  tm.{attr} = {v}")
p1.close()

print("\n" + "=" * 74)
print("2. 非幂等 producer：发送后仍是 -1")
print("=" * 74)
p2 = KafkaProducer(bootstrap_servers=BS, max_block_ms=10000,
                   enable_idempotence=False)
print(f"  enable_idempotence = {p2.config.get('enable_idempotence')}")
p2.send(T, b"non-idempotent").get(timeout=15)
p2.flush(timeout=15)
show(p2, "发送后")
print("  → 非幂等 producer 不申请 PID，批次里 producer_id = -1")
p2.close()

print("\n" + "=" * 74)
print("3. 幂等只在【单会话】内有效 —— 重启 producer 后 PID 变吗？")
print("=" * 74)
pids = []
for i in range(3):
    p = KafkaProducer(bootstrap_servers=BS, max_block_ms=10000)
    p.send(T, f"sess-{i}".encode()).get(timeout=15)
    p.flush(timeout=10)
    pae = p._transaction_manager.producer_id_and_epoch
    pids.append((pae.producer_id, pae.epoch))
    print(f"  第 {i+1} 个 producer 实例: PID={pae.producer_id} epoch={pae.epoch}")
    p.close()

if len(set(p for p, _ in pids)) > 1:
    print(f"  → PID 各不相同: {[p for p, _ in pids]}")
    print("  ⚠️ 不同会话 PID 不同 → 幂等【跨会话失效】，重启后重复无法去重")
else:
    print(f"  → PID 相同: {pids}")

print("\n" + "=" * 74)
print("4. 用消费者验证消息确实写入（含 producer_id 元数据）")
print("=" * 74)
c = KafkaConsumer(T, bootstrap_servers=BS, group_id=G,
                  auto_offset_reset="earliest", enable_auto_commit=False,
                  consumer_timeout_ms=8000)
n = 0
for msg in c:
    n += 1
    if n <= 4:
        print(f"  offset={msg.offset} value={msg.value} "
              f"partition={msg.partition}")
print(f"  共 {n} 条")
c.close()

try:
    admin.delete_topics([T])
    print("\n已清理 topic")
except Exception as e:
    print(f"cleanup: {type(e).__name__}")
admin.close()
