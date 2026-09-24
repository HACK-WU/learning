"""课 4：读 send() 的核心路径 —— 批次累加 + Sender 唤醒 + 背压。

聚焦三件事：
  1. send() 到底做了什么（是不是立刻发？）
  2. 批次怎么攒（accumulator.append）
  3. 背压怎么发生（buffer_memory 耗尽）
  4. Sender 线程怎么被唤醒
"""
import inspect

from kafka import KafkaProducer
from kafka.producer import record_accumulator, sender

# ============ 1. send() 的核心几行（跳过 docstring） ============
print("=" * 70)
print("1. send() 核心逻辑（去 docstring）")
print("=" * 70)
src = inspect.getsource(KafkaProducer.send)
lines = src.split("\n")
# 找 docstring 结束
end = 0
for i, l in enumerate(lines):
    if '"""' in l and i > 0:
        end = i
        break
core = "\n".join(lines[end + 1:])
print(core)

# ============ 2. _wait_on_metadata / accumulator.append ============
print("\n" + "=" * 70)
print("2. accumulator.append（批次累加）")
print("=" * 70)
try:
    from kafka.producer.record_accumulator import RecordAccumulator
    print(inspect.getsource(RecordAccumulator.append)[:2500])
except Exception as e:
    print(f"{type(e).__name__}: {e}")

# ============ 3. 背压：buffer_memory 相关的分配 ============
print("\n" + "=" * 70)
print("3. 背压：_allocate / buffer_memory")
print("=" * 70)
try:
    print(inspect.getsource(RecordAccumulator._allocate)[:2000])
except Exception as e:
    print(f"{type(e).__name__}: {e}")

# ============ 4. Sender 唤醒 ============
print("\n" + "=" * 70)
print("4. Sender 线程 run_once（谁在真正发送）")
print("=" * 70)
try:
    from kafka.producer.sender import Sender
    s = inspect.getsource(Sender.run_once)
    print(s[:2000])
except Exception as e:
    print(f"{type(e).__name__}: {e}")

# ============ 5. ready()：什么条件下批次才算可发 ============
print("\n" + "=" * 70)
print("5. accumulator.ready()（批次就绪条件）")
print("=" * 70)
try:
    print(inspect.getsource(RecordAccumulator.ready)[:2200])
except Exception as e:
    print(f"{type(e).__name__}: {e}")
