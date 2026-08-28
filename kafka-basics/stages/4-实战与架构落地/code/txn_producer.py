"""课 9 实操：事务现场演示（kafka-python >= 2.2.0）

- 事务 1：发 3 条（txn-A-*）后提交 -> 对 read_committed 消费者可见
- 事务 2：发 2 条（txn-B-*）后挂 30 秒再中止
  -> 挂住期间另开终端跑（兑现课 8 的预告）：
     docker exec -it kafka /opt/kafka/bin/kafka-transactions.sh \
       --bootstrap-server localhost:9092 list
     可看到 Ongoing 状态的事务
  -> abort 之后这 2 条对 read_committed 永不可见（跑 consumer_committed.py 验证）
"""
import time
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers='localhost:9092',
    transactional_id='points-txn-demo-1',   # 课 8：稳定身份证，跨重启不变
    value_serializer=str.encode,
)

producer.init_transactions()   # 上岗登记：领 PID + 提升 epoch（挡住僵尸前任）

# —— 事务 1：正常提交 ——
producer.begin_transaction()
for i in range(3):
    producer.send('points', value=f'txn-A-{i}').get(timeout=10)
producer.commit_transaction()  # 3 条一次性对 read_committed 可见
print('事务 1 已提交（txn-A-0/1/2）')

# —— 事务 2：故意反悔 ——
producer.begin_transaction()
for i in range(2):
    producer.send('points', value=f'txn-B-{i}').get(timeout=10)
print('事务 2 已发送 2 条，保持 Ongoing 30 秒——')
print('  另开一个终端跑: docker exec -it kafka /opt/kafka/bin/'
      'kafka-transactions.sh --bootstrap-server localhost:9092 list')
time.sleep(30)
producer.abort_transaction()   # 撤销：这 2 条对 read_committed 永不可见
print('事务 2 已中止（txn-B-0/1 作废）')

producer.close()
print('事务演示结束，接着跑 consumer_committed.py 看可见性')
