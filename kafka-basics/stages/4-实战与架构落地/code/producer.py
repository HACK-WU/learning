"""课 9 实操：最小可用的生产者（kafka-python 3.x）

发送 10 条咖啡订单到 orders topic：
- key = 用户名 -> 同一用户的订单固定进同一分区（课 5 分区策略）
- acks='all' -> 等 ISR 全体确认（课 5 发送可靠性）
- future.get() -> 等签收回执：分区 + 位移（教学演示用逐条确认）
"""
import json
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers='localhost:9092',                        # 课 3 起的本地 broker
    key_serializer=str.encode,                                 # key: str -> bytes
    value_serializer=lambda v: json.dumps(v).encode('utf-8'),  # value: dict -> JSON bytes
    acks='all',                                                # 关键参数永远显式写
)

# 三个用户各下几单：观察输出里同一 key 是否总落在同一分区
orders = []
for i in range(10):
    user = ['alice', 'bob', 'carol'][i % 3]
    orders.append({'order_id': 100 + i, 'user': user, 'item': 'latte'})

for order in orders:
    future = producer.send('orders', key=order['user'], value=order)
    meta = future.get(timeout=10)                              # 等回执：真正送达 broker
    print(f'已送达 {meta.topic}[{meta.partition}] @{meta.offset} '
          f'key={order["user"]} order_id={order["order_id"]}')

producer.flush()   # 发车口令：清空缓冲区（本例逐条 get 已确认，此行是习惯养成）
producer.close()   # 关闭后台发送线程
print('生产者完成，共发送', len(orders), '条')
