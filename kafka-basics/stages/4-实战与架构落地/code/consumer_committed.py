"""课 9 实操：read_committed 消费者——事务可见性对比实验（课 8 进阶挑战的兑现）

跑在 txn_producer.py 之后：只读已提交数据，只能看到 txn-A 三条；
删掉 isolation_level 那一行再跑（默认 read_uncommitted），txn-B 也会现形。
"""
from kafka import KafkaConsumer

consumer = KafkaConsumer(
    'points',
    bootstrap_servers='localhost:9092',
    group_id='audit-committed',
    auto_offset_reset='earliest',
    isolation_level='read_committed',   # 课 8：只读已提交（不配这行 = 默认读全部）
)

try:
    for msg in consumer:
        print(f'只读已提交: {msg.value.decode("utf-8")}')
except KeyboardInterrupt:
    pass
finally:
    consumer.close()
