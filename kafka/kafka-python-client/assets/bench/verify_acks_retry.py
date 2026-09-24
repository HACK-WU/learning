"""课 4：acks / retries / 超时链路实测。

源码已确认：acks=-1（默认）、retries=inf、request_timeout_ms=30000、
delivery_timeout_ms=120000、max_block_ms=60000。

本节实测：
  1. 三档 acks 的实际行为差异（延迟）
  2. retries=inf 是不是真无限（配合 delivery_timeout）
  3. 超时三兄弟的关系：谁先触发
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
T = "l4-acks-test"

from kafka import KafkaProducer, KafkaAdminClient
from kafka.admin import NewTopic

admin = KafkaAdminClient(bootstrap_servers=BS, request_timeout_ms=15000)
try:
    r = admin.create_topics([NewTopic(T, num_partitions=1, replication_factor=1)])
    for it in r.get("topics", []):
        print(f"create: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"create: {type(e).__name__}: {str(e)[:80]}")
time.sleep(1)

print("=" * 70)
print("1. 三档 acks 的实测延迟（各发 100 条，flush 计时）")
print("=" * 70)
print(f"  {'acks':<8}{'说明':<22}{'100条耗时':<14}{'单条均值'}")
for acks, desc in ((0, "不等确认（最快最不可靠）"),
                   (1, "等 leader 落盘"),
                   (-1, "等所有 ISR 落盘（默认）")):
    try:
        p = KafkaProducer(bootstrap_servers=BS, acks=acks,
                          linger_ms=0, max_block_ms=10000)
        t0 = time.time()
        for i in range(100):
            p.send(T, f"a-{acks}-{i}".encode())
        p.flush(timeout=30)
        el = time.time() - t0
        print(f"  {acks:<8}{desc:<22}{el*1000:>8.1f}ms   {el*1000/100:>6.2f}ms")
        p.close(timeout=5)
    except Exception as e:
        print(f"  {acks:<8}{desc:<22} ✗ {type(e).__name__}: {str(e)[:70]}")

print("\n" + "=" * 70)
print("2. retries=inf 的真相：是不是真无限？")
print("=" * 70)
from kafka.producer.kafka import KafkaProducer as KP
print(f"  DEFAULT_CONFIG['retries']            = {KP.DEFAULT_CONFIG.get('retries')}")
print(f"  DEFAULT_CONFIG['delivery_timeout_ms'] = {KP.DEFAULT_CONFIG.get('delivery_timeout_ms')}")
print(f"  DEFAULT_CONFIG['request_timeout_ms']  = {KP.DEFAULT_CONFIG.get('request_timeout_ms')}")
print(f"  DEFAULT_CONFIG['max_block_ms']        = {KP.DEFAULT_CONFIG.get('max_block_ms')}")
print(f"  DEFAULT_CONFIG['retry_backoff_ms']    = {KP.DEFAULT_CONFIG.get('retry_backoff_ms')}")
print("""
  → retries=inf 不是「无限重试」，而是「不限次数，但受 delivery_timeout_ms 封顶」。
    真正决定「一条消息最多活多久」的是 delivery_timeout_ms（默认 120s）。
""")

print("=" * 70)
print("3. 超时三兄弟的关系（源码注释佐证）")
print("=" * 70)
import inspect
src = inspect.getsource(KP)
for key in ("max_block_ms (int)", "request_timeout_ms (int)",
            "delivery_timeout_ms (int)", "retries (int)"):
    for i, line in enumerate(src.split("\n"), 1):
        if key in line:
            # 取该参数的说明段
            seg = src.split("\n")[i - 1:i + 6]
            print(f"  --- {key} ---")
            for s in seg:
                print(f"    {s.strip()[:100]}")
            break

print("\n" + "=" * 70)
print("4. 实测：delivery_timeout 会不会真的终止重试")
print("=" * 70)
try:
    p = KafkaProducer(bootstrap_servers=BS,
                      delivery_timeout_ms=3000,   # 3 秒封顶
                      request_timeout_ms=1000,
                      max_block_ms=5000,
                      retries=10 ** 9)
    t0 = time.time()
    futs = []
    for i in range(5):
        futs.append(p.send(T, f"dt-{i}".encode()))
    ok = fail = 0
    for f in futs:
        try:
            f.get(timeout=10)
            ok += 1
        except Exception as e:
            fail += 1
            print(f"    ✗ {type(e).__name__}: {str(e)[:90]}")
    print(f"  成功 {ok} / 失败 {fail}，总耗时 {time.time()-t0:.2f}s")
    p.close(timeout=5)
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")

print("\n" + "=" * 70)
try:
    r = admin.delete_topics([T])
    for it in r.get("topics", []):
        print(f"delete: {it.get('name')} error_code={it.get('error_code')}")
except Exception as e:
    print(f"delete: {type(e).__name__}: {str(e)[:80]}")
admin.close()
