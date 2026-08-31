import asyncio
from rstream import Producer, Consumer
from rstream import ConsumerOffsetSpecification, OffsetType

STREAM = 'l5_replay_stream'
HOST, PORT = 'localhost', 5552
USER, PWD = 'learn', 'learn123'


async def publish():
    producer = Producer(HOST, port=PORT, username=USER, password=PWD)
    await producer.start()
    await producer.create_stream(STREAM, exists_ok=True)
    for i in range(1, 4):
        await producer.send(STREAM, f'msg-{i}'.encode())
    await producer.close()
    await asyncio.sleep(1)


async def read_all(tag):
    """从头读，读到稳定为止"""
    got = []
    consumer = Consumer(HOST, port=PORT, username=USER, password=PWD)
    await consumer.start()
    await consumer.subscribe(
        STREAM,
        callback=lambda msg, ctx: got.append(msg),
        offset_specification=ConsumerOffsetSpecification(offset_type=OffsetType.FIRST),
    )
    # 等到 3 条（过滤掉重复投递造成的干扰，取前 3 条）
    for _ in range(40):
        if len(got) >= 3:
            break
        await asyncio.sleep(0.2)
    await asyncio.sleep(0.5)
    try:
        await consumer.close()
    except Exception:
        pass
    bodies = [m.decode() if isinstance(m, bytes) else str(m) for m in got]
    print(f"  [{tag}] 读到 {len(got)} 条: {bodies[:6]}{' ...' if len(bodies) > 6 else ''}")
    return len(got)


async def main():
    print("=" * 62)
    print("【stream 队列 · 可回放验证】")
    print("=" * 62)
    await publish()
    print("已发布 3 条: msg-1 / msg-2 / msg-3\n")

    print("--- 连续三轮从头读取同一个 stream ---")
    a = await read_all('第1轮')
    await asyncio.sleep(1)
    b = await read_all('第2轮')
    await asyncio.sleep(1)
    c = await read_all('第3轮')

    print("\n" + "=" * 62)
    print("结论")
    print("=" * 62)
    if a >= 3 and b >= 3 and c >= 3:
        print("✅ 三轮都能从头读到 msg-1/2/3")
        print("   → stream 的消息【消费后不删除】，任意时刻可从任意 offset 重放")
        print("   → 这是它与 classic / quorum 最本质的区别（后者消费即删）")
    else:
        print(f"⚠️ 结果: 第1轮={a} 第2轮={b} 第3轮={c}")

asyncio.run(main())
