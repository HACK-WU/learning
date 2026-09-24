"""课 2：枚举 AIOKafkaProducer 实例真实属性，找到 acks 的实际存储位置。

前几版都在猜属性名（_acks / acks 都不对）。这版不猜：vars() 全列。
"""
import asyncio

from aiokafka import AIOKafkaProducer


async def main():
    cases = [
        ("默认", {}),
        ("idempotence=True", {"enable_idempotence": True}),
        ("idempotence=False", {"enable_idempotence": False}),
        ("acks=-1", {"acks": -1}),
        ("acks=1", {"acks": 1}),
        ("acks=0", {"acks": 0}),
    ]

    # 第一遍：默认实例全量属性（找 acks 相关）
    p = AIOKafkaProducer(bootstrap_servers="kafka-1:9092")
    print("=== 默认实例里含 ack/idempotent 的属性 ===")
    for k, v in vars(p).items():
        kl = k.lower()
        if "ack" in kl or "idempot" in kl:
            print(f"  {k:<32} = {v!r}")
    await p.stop() if hasattr(p, "stop") else None

    print("\n=== 各配置下 acks 实际生效值 ===")
    for label, kw in cases:
        try:
            pp = AIOKafkaProducer(bootstrap_servers="kafka-1:9092", **kw)
            vs = vars(pp)
            # 找 acks 值
            acks_val = None
            idem_val = None
            for k, v in vs.items():
                kl = k.lower()
                if kl.endswith("acks") or kl == "acks":
                    acks_val = v
                if "idempot" in kl:
                    idem_val = v
            print(f"  {label:<20} → acks={acks_val!r:<8} idempotence={idem_val!r}")
            try:
                await pp.stop()
            except Exception:
                pass
        except Exception as e:
            print(f"  {label:<20} → 报错 {type(e).__name__}: {str(e)[:70]}")


asyncio.run(main())

print("\n=== kafka-python 对照 ===")
from kafka import KafkaProducer
print(f"  acks                = {KafkaProducer.DEFAULT_CONFIG['acks']!r}")
print(f"  enable_idempotence  = {KafkaProducer.DEFAULT_CONFIG.get('enable_idempotence')!r}")
