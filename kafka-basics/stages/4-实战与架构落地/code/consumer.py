"""课 9 实操：带手动位移提交的消费者（kafka-python 3.x）

- group_id：消费者组身份（课 6）
- auto_offset_reset='earliest'：组内无位移时从头读（课 6）
- enable_auto_commit=False：关自动提交，处理完一条提交一条
  -> 先处理后提交 = at-least-once（崩溃重读，靠业务幂等兜底，课 8）
- 消费完存量后程序会安静挂住：不是死机，是长驻服务在等新消息
"""
import json
from kafka import KafkaConsumer

consumer = KafkaConsumer(
    'orders',
    bootstrap_servers='localhost:9092',
    group_id='points-service',           # 换一个组 ID = 一套全新进度
    auto_offset_reset='earliest',
    enable_auto_commit=False,            # 提交时机自己拿捏
    key_deserializer=lambda k: k.decode('utf-8'),
    value_deserializer=lambda m: json.loads(m.decode('utf-8')),
)

try:
    for msg in consumer:                 # 这一行背后就是课 6 的 poll 循环
        print(f'处理订单 {msg.value["order_id"]}（用户 {msg.key}）'
              f'来自 {msg.topic}[{msg.partition}]@{msg.offset}')
        # ...真实业务放这里：给用户加积分...
        consumer.commit()                # 处理完一条提交一条
except KeyboardInterrupt:
    print('收到 Ctrl+C，优雅退出')
finally:
    consumer.close()                     # 主动离组：同组成员立刻再均衡接手分区
