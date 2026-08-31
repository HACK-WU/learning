# points_consumer.py：积分服务（消费者）
# 知识点回指：课 6（消费者组、手动提交）、课 8（至少一次 + 幂等）、设计决策 1/2

from collections import defaultdict

from kafka import KafkaConsumer, KafkaProducer
from kafka.errors import KafkaError

from common import (
    BOOTSTRAP_SERVERS, TOPIC_ORDERS, TOPIC_DLQ,
    MAX_RETRY, setup_logging, to_json_bytes, from_json_bytes,
)

log = setup_logging('points-service')

# 幂等去重表（课 8：消费端幂等）
# 真实项目用数据库唯一索引 / Redis SET，这里用内存字典演示原理
processed_events = set()
# 失败计数：同一 event_id 失败次数，超过 MAX_RETRY 进 DLQ
fail_count = defaultdict(int)
# 模拟积分账本
points_ledger = defaultdict(int)


def build_consumer():
    return KafkaConsumer(
        TOPIC_ORDERS,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id='points-service',       # 组 ID 就是服务身份（课 6）
        auto_offset_reset='earliest',
        enable_auto_commit=False,        # 关键：手动提交（反例对照坑 7）
        value_deserializer=from_json_bytes,
        key_deserializer=lambda k: k.decode('utf-8') if k else None,
    )


def build_dlq_producer():
    return KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        acks='all',
        enable_idempotence=True,
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        value_serializer=to_json_bytes,
    )


def add_points(event):
    """业务处理：按事件类型加减积分。缺字段会抛异常 → 被外层捕获进重试/DLQ 逻辑"""
    amount = event['amount']          # 坏消息缺这个字段 → KeyError
    user = event['user_id']
    event_type = event['event_type']

    if event_type == 'OrderCreated':
        delta = int(amount)
    elif event_type == 'OrderPaid':
        delta = int(amount * 2)
    elif event_type == 'OrderCancelled':
        delta = -int(amount)
    else:
        raise ValueError(f'未知事件类型: {event_type}')

    points_ledger[user] += delta
    return delta


def main():
    consumer = build_consumer()
    dlq = build_dlq_producer()
    log.info('积分服务启动，订阅 %s，group=points-service', TOPIC_ORDERS)

    try:
        for msg in consumer:
            event = msg.value
            event_id = event.get('event_id', '<unknown>')

            # 第一层幂等：已处理过就跳过（至少一次语义下必然会重复投递）
            if event_id in processed_events:
                log.info('跳过已处理事件: %s', event_id)
                # 注意：已处理也要提交位移，否则重启后会重复消费
                consumer.commit()
                continue

            try:
                delta = add_points(event)
                processed_events.add(event_id)
                log.info('加分成功: %s 用户=%s 变动=%+d 当前积分=%d',
                         event_id, event['user_id'], delta,
                         points_ledger[event['user_id']])

                # 关键：处理成功之后才提交位移（课 6：先处理后提交 = 不丢消息）
                consumer.commit()

            except Exception as exc:
                fail_count[event_id] += 1
                log.warning('处理失败(%d/%d): %s 原因=%s',
                            fail_count[event_id], MAX_RETRY, event_id, exc)

                if fail_count[event_id] >= MAX_RETRY:
                    # 进 DLQ：保留原始消息 + 失败原因，主分区继续前进
                    dlq.send(
                        TOPIC_DLQ,
                        value={
                            'event_id': event_id,
                            'original': event,
                            'error': str(exc),
                            'topic': msg.topic,
                            'partition': msg.partition,
                            'offset': msg.offset,
                            'failed_at': 'points-service',
                        },
                    )
                    dlq.flush()
                    log.error('已投递 DLQ: %s（主分区继续前进，不被坏消息阻塞）', event_id)
                    processed_events.add(event_id)  # 标记为已处置，避免反复重试
                    consumer.commit()
                # 未达重试上限：不提交位移，下轮继续尝试（退避重试策略）
    except KafkaError as exc:
        log.error('Kafka 异常: %s', exc)
    finally:
        log.info('积分账本最终状态: %s', dict(points_ledger))
        consumer.close()
        dlq.close()


if __name__ == '__main__':
    main()
