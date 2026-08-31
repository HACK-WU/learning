# risk_consumer.py：风控服务（事务版消费者）
# 知识点回指：课 8（事务、read_committed、send_offsets_to_transaction）、设计决策 1

import time
from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import KafkaError
from kafka.structs import TopicPartition, OffsetAndMetadata

from common import (
    BOOTSTRAP_SERVERS, TOPIC_ORDERS, TOPIC_RISK_RESULT, TOPIC_DLQ,
    setup_logging, to_json_bytes, from_json_bytes,
)

log = setup_logging('risk-service')

# 事务 ID 必须跨重启稳定、且每个实例唯一（课 8）：两个实例共用会互相围栏
TRANSACTIONAL_ID = 'risk-service-instance-1'
CONSUMER_GROUP = 'risk-service'

# 风控规则：单笔金额超过阈值需要人工复核
AMOUNT_THRESHOLD = 400.0


def build_consumer():
    return KafkaConsumer(
        TOPIC_ORDERS,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id=CONSUMER_GROUP,
        auto_offset_reset='earliest',
        enable_auto_commit=False,
        # 只读已提交的消息：未提交的事务消息对消费者不可见（课 8）
        isolation_level='read_committed',
        value_deserializer=from_json_bytes,
    )


def build_txn_producer():
    return KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        acks='all',
        enable_idempotence=True,          # 事务必须开幂等（课 8）
        transactional_id=TRANSACTIONAL_ID,
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        value_serializer=to_json_bytes,
    )


def judge(event):
    """风控判定：纯计算，输入输出都在 Kafka 内 —— 这才适合用事务

    注意：这里**不用** event.get('amount', 0) 兜底。
    缺 amount 说明是坏消息，若兜底成 0 会被静默判为 PASS ——
    风控场景里「静默放行一条没看清的订单」比「报错」危险得多（设计决策 2）。
    缺字段就抛异常，由上层捕获后进 DLQ。
    """
    if 'amount' not in event:
        raise KeyError('amount')
    amount = event['amount']

    if amount > AMOUNT_THRESHOLD:
        return 'REVIEW', f'单笔金额 {amount} 超过阈值 {AMOUNT_THRESHOLD}'
    if event.get('event_type') == 'OrderCancelled':
        return 'PASS', '取消订单无需风控'
    return 'PASS', '正常'


def send_to_dlq(event_id, event, error, msg):
    """坏消息出口：投进 DLQ，保证主分区继续前进"""
    dlq = KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        acks='all',
        enable_idempotence=True,
        value_serializer=to_json_bytes,
    )
    try:
        dlq.send(TOPIC_DLQ, value={
            'event_id': event_id,
            'original': event,
            'error': error,
            'topic': msg.topic,
            'partition': msg.partition,
            'offset': msg.offset,
            'failed_at': 'risk-service',
        })
        dlq.flush()
    finally:
        dlq.close()


def main():
    consumer = build_consumer()
    producer = build_txn_producer()

    # 事务第一步：初始化（会提升 epoch、围栏掉同 ID 的旧实例 = 僵尸实例）
    producer.init_transactions()
    log.info('风控服务启动，事务 ID=%s', TRANSACTIONAL_ID)

    try:
        for msg in consumer:
            event = msg.value
            event_id = event.get('event_id', '<unknown>')

            try:
                verdict, reason = judge(event)

                # 事务第二步：开启
                producer.begin_transaction()

                # 事务第三步：写入判定结果
                producer.send(
                    TOPIC_RISK_RESULT,
                    key=event.get('user_id'),
                    value={
                        'event_id': event_id,
                        'verdict': verdict,
                        'reason': reason,
                        'judged_at': int(time.time() * 1000),
                    },
                )

                # 事务第四步（最关键）：把消费位移一起纳入事务
                # 这样「消费了这条消息」和「写出了判定结果」是原子的：
                # 要么都发生，要么都不发生 → 不会出现"消息没处理但位移提交了"
                # 注意：offsets 的 key 必须是 TopicPartition，value 是 OffsetAndMetadata
                #       提交的是「下一条要读的位移」，所以是 offset + 1
                offsets = {
                    TopicPartition(msg.topic, msg.partition):
                        OffsetAndMetadata(msg.offset + 1, None)
                }
                # group_metadata 用完整元数据（而非裸 group_id 字符串），
                # 可启用 KIP-447 的 broker 端围栏，挡掉过期的消费者实例
                producer.send_offsets_to_transaction(offsets, consumer.group_metadata())

                # 事务第五步：提交
                producer.commit_transaction()

                log.info('判定完成（事务已提交）: %s → %s（%s）',
                         event_id, verdict, reason)

            except KeyError as exc:
                # 坏消息（缺关键字段）：不能让风控静默放行，也不能无限重试阻塞分区
                # 投 DLQ 并跳过，与设计决策 2 保持一致
                log.error('坏消息，投 DLQ 并跳过: %s 缺字段=%s', event_id, exc)
                send_to_dlq(event_id, event, str(exc), msg)
                consumer.commit()

            except KafkaError as exc:
                # 事务失败必须中止，否则后续 send 会处于不确定状态
                try:
                    producer.abort_transaction()
                except Exception:
                    pass
                log.error('事务中止: %s 原因=%s', event_id, exc)
                time.sleep(1)

    except KafkaError as exc:
        log.error('Kafka 异常: %s', exc)
    finally:
        consumer.close()
        producer.close()


if __name__ == '__main__':
    main()
