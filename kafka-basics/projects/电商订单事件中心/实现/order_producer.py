# order_producer.py：订单服务（生产者）
# 知识点回指：课 5（acks、分区策略、幂等）、课 9（写生产者）、课 10（事件命名用过去式）

import random
import time
from kafka import KafkaProducer
from kafka.errors import KafkaError

from common import (
    BOOTSTRAP_SERVERS, TOPIC_ORDERS, setup_logging, to_json_bytes,
)

log = setup_logging('order-producer')

# 事件类型全部使用「过去式事实」（课 10：事件 vs 命令）
# 反例：SendPoints / CallRiskEngine 这类命令式命名会让下游耦合回来
EVENT_TYPES = ['OrderCreated', 'OrderPaid', 'OrderCancelled']

BAD_MESSAGE_RATE = 0.05  # 5% 的坏消息，用来演示 DLQ 的效果


def build_producer():
    return KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        # 显式写关键参数，不依赖默认值（课 9 的教训）
        acks='all',                  # 等待 ISR 全体确认（课 7）：不丢消息的底线
        enable_idempotence=True,     # 幂等（课 8）：消除内部重试导致的重复
        linger_ms=10,                # 攒 10ms 再发，提高吞吐（课 5 的批次思想）
        batch_size=16384,
        retries=3,
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        value_serializer=to_json_bytes,
    )


def on_send_success(metadata):
    log.info('发送成功: topic=%s partition=%d offset=%d',
             metadata.topic, metadata.partition, metadata.offset)


def on_send_error(record, exc):
    # 关键：不检查回调 = 静默丢消息（反例对照坑 4）
    # 真实项目这里应把失败消息落盘或写入 outbox，而不是只打日志
    log.error('发送失败: event_id=%s 原因=%s（生产环境应落盘重试）',
              record.get('event_id'), exc)


def main():
    producer = build_producer()
    log.info('订单服务启动，目标 topic=%s', TOPIC_ORDERS)

    try:
        for i in range(1, 31):
            # 用 user_id 作 key（课 5）：保证同一用户的订单进入同一分区 → 保序
            user_id = f'user-{random.randint(1, 5):02d}'
            event = {
                'event_id': f'evt-{i:04d}',      # 幂等去重的业务主键
                'event_type': random.choice(EVENT_TYPES),
                'user_id': user_id,
                'order_id': f'order-{i:04d}',
                'amount': round(random.uniform(10, 500), 2),
                'ts': int(time.time() * 1000),
            }

            # 故意制造坏消息：缺字段 / 类型错误，让消费者处理失败 → 进 DLQ
            if random.random() < BAD_MESSAGE_RATE:
                event.pop('amount')
                log.warning('注入一条坏消息（缺 amount 字段）: %s', event['event_id'])

            future = producer.send(
                TOPIC_ORDERS,
                key=user_id,
                value=event,
            )
            # 异步发送 + 回调检查（课 9：Future 才是签收单）
            future.add_callback(on_send_success)
            future.add_errback(lambda exc, e=event: on_send_error(e, exc))

            time.sleep(0.3)

        # flush 把缓冲区里剩余的消息全部发出去（反例对照坑 6）
        producer.flush()
        log.info('30 条事件已全部 flush（含约 5%% 坏消息，用于演示 DLQ）')
    except KafkaError as exc:
        log.error('Kafka 异常: %s', exc)
    finally:
        producer.close()


if __name__ == '__main__':
    main()
