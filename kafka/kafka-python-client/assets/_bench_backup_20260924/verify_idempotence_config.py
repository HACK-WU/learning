"""课 6：幂等配置的【静默关闭】vs【抛异常】—— 实测两种行为。

源码结论（KIP-679）：
  - 默认 enable_idempotence=True, acks='all', retries=inf
  - 若用户【显式提供】冲突配置（acks=0 / retries=0 / inflight>5）
    → 静默关闭幂等 + warning
  - 若用户【显式设置】enable_idempotence=True
    → 冲突直接 raise KafkaConfigurationError

要测四组：
  A. 全默认           → 幂等开？
  B. acks=0（隐式冲突）→ 静默关闭？
  C. acks=0 + 显式 True → 抛异常？
  D. enable_idempotence=False → 明确关闭
"""
import logging
import socket
import sys

from kafka import KafkaProducer
from kafka.errors import KafkaConfigurationError

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
print(f"brokers: {BS}\n")

# 捕获 warning
logging.basicConfig(level=logging.WARNING)
caught = []


class H(logging.Handler):
    def emit(self, r):
        caught.append(r.getMessage()[:200])


logging.getLogger().addHandler(H())


def probe(name, **kw):
    """建一个 producer，报告幂等最终状态"""
    caught.clear()
    try:
        p = KafkaProducer(bootstrap_servers=BS, max_block_ms=8000, **kw)
        idem = p.config.get("enable_idempotence")
        acks = p.config.get("acks")
        retries = p.config.get("retries")
        inflight = p.config.get("max_in_flight_requests_per_connection")
        print(f"  [{name}]")
        print(f"     enable_idempotence = {idem}")
        print(f"     acks={acks}  retries={retries}  inflight={inflight}")
        if caught:
            for c in caught[:2]:
                print(f"     ⚠️ warning: {c[:150]}")
        else:
            print("     （无 warning）")
        p.close()
        return idem
    except KafkaConfigurationError as e:
        print(f"  [{name}]")
        print(f"     ✗ 抛异常 KafkaConfigurationError: {str(e)[:180]}")
        return "RAISE"
    except Exception as e:
        print(f"  [{name}]")
        print(f"     ✗ {type(e).__name__}: {str(e)[:150]}")
        return "ERR"


print("=" * 74)
print("A. 全默认（KIP-679：幂等应默认开启）")
print("=" * 74)
probe("全默认")

print("\n" + "=" * 74)
print("B. 只给 acks=0（隐式冲突 → 预期：静默关闭 + warning）")
print("=" * 74)
probe("acks=0", acks=0)

print("\n" + "=" * 74)
print("C. acks=0 + 显式 enable_idempotence=True（预期：抛异常）")
print("=" * 74)
probe("acks=0 + 显式True", acks=0, enable_idempotence=True)

print("\n" + "=" * 74)
print("D. retries=0（隐式冲突 → 预期：静默关闭）")
print("=" * 74)
probe("retries=0", retries=0)

print("\n" + "=" * 74)
print("E. inflight=10 > 5（隐式冲突 → 预期：静默关闭）")
print("=" * 74)
probe("inflight=10", max_in_flight_requests_per_connection=10)

print("\n" + "=" * 74)
print("F. 显式 enable_idempotence=False（明确关闭）")
print("=" * 74)
probe("显式False", enable_idempotence=False)

print("\n" + "=" * 74)
print("G. transactional_id 设置（自动强制幂等）")
print("=" * 74)
probe("txn_id", transactional_id="l6-txn-test")

print("\n" + "=" * 74)
print("H. transactional_id + acks=0（事务路径严格 → 预期抛异常）")
print("=" * 74)
probe("txn_id + acks=0", transactional_id="l6-txn-2", acks=0)
