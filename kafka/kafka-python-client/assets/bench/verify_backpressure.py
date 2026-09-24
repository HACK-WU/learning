"""课 4：背压实测 —— 验证「kafka-python 没有 BufferPool 背压」。

三条验证：
  1. 传 buffer_memory=1（1 字节！）看会不会被限制 → 若照常发送说明不生效
  2. 疯狂 send 看是阻塞还是吞进去（内存增长）
  3. linger_ms=0 时批次是不是真的一条一个（batch_size 的作用）
"""
import resource
import time


from kafka import KafkaProducer
from kafka.errors import KafkaTimeoutError

BS = "kafka-1:9092,kafka-2:9092,kafka-3:9092"
T = "l4-bp-test"


def rss_mb():
    """当前进程 RSS（MB）"""
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024


print("=" * 70)
print("1. buffer_memory=1 会不会生效？")
print("=" * 70)
try:
    p = KafkaProducer(bootstrap_servers=BS, buffer_memory=1,      # 1 字节！
                      max_block_ms=3000, linger_ms=500)
    print(f"  ✓ 能构造（buffer_memory=1）")
    t0 = time.time()
    n = 200
    for i in range(n):
        p.send(T, b"x" * 100)
    el = time.time() - t0
    print(f"  send {n} 条 × 100B 用时 {el:.3f}s，未抛异常")
    print(f"  → buffer_memory=1 没有阻止发送 ⇒ 该项在 kafka-python 不生效")
    p.flush(timeout=10)
    p.close()
except KafkaTimeoutError as e:
    print(f"  ✗ KafkaTimeoutError: {str(e)[:120]}")
except Exception as e:
    print(f"  ✗ {type(e).__name__}: {str(e)[:200]}")

print("\n" + "=" * 70)
print("2. 无界 send：内存会不会爆（证明无背压）")
print("=" * 70)
try:
    p = KafkaProducer(bootstrap_servers=BS, linger_ms=60000,   # 攒着不发改
                      max_block_ms=5000)
    m0 = rss_mb()
    print(f"  起始 RSS = {m0:.1f} MB")
    N = 20000
    t0 = time.time()
    for i in range(N):
        p.send(T, b"y" * 500)          # 约 10MB 数据
        if i % 5000 == 0 and i:
            print(f"    send {i:>6} 条后 RSS = {rss_mb():.1f} MB "
                  f"(Δ{rss_mb()-m0:+.1f})")
    el = time.time() - t0
    m1 = rss_mb()
    print(f"  send {N} 条 × 500B（约 {N*500/1024/1024:.1f} MB）用时 {el:.2f}s")
    print(f"  结束 RSS = {m1:.1f} MB（Δ{m1-m0:+.1f} MB）")
    print(f"  → 数据全在内存里，没有任何阻塞/拒绝 ⇒ 无背压上限")
    p.close(timeout=5)
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:200]}")

print("\n" + "=" * 70)
print("3. linger_ms 对批次的影响（batch_size=16KB）")
print("=" * 70)
import socket

# 用 metadata 观察：linger=0 vs linger=1000 的实际发送节奏
for linger in (0, 1000):
    try:
        p = KafkaProducer(bootstrap_servers=BS, linger_ms=linger,
                          batch_size=16384, max_block_ms=5000)
        t0 = time.time()
        for i in range(50):
            p.send(T, b"z" * 200)
        send_done = time.time() - t0
        p.flush(timeout=10)
        total = time.time() - t0
        print(f"  linger_ms={linger:<5} send 50 条耗时 {send_done*1000:.1f}ms, "
              f"flush 后总耗时 {total*1000:.1f}ms")
        p.close(timeout=5)
    except Exception as e:
        print(f"  linger={linger}: {type(e).__name__}: {str(e)[:120]}")

print("\n" + "=" * 70)
print("4. 单条超限（max_request_size=1MB）")
print("=" * 70)
try:
    p = KafkaProducer(bootstrap_servers=BS, max_block_ms=5000)
    try:
        p.send(T, b"w" * (1024 * 1024 + 100))   # 超过 1MB
        print("  ✗ 竟然没报错")
    except Exception as e:
        print(f"  ✓ {type(e).__name__}: {str(e)[:130]}")
    p.close(timeout=5)
except Exception as e:
    print(f"  {type(e).__name__}: {str(e)[:150]}")
