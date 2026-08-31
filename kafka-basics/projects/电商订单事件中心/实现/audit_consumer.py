# audit_consumer.py：审计服务（全量留痕，事件溯源雏形）
# 知识点回指：课 4（消息不随消费删除）、课 6（消费者组广播）、课 10（事件溯源拓扑）

from kafka import KafkaConsumer
from kafka.errors import KafkaError

from common import (
    BOOTSTRAP_SERVERS, TOPIC_ORDERS,
    setup_logging, from_json_bytes,
)

log = setup_logging('audit-service')

# 审计的留痕容器：模拟"只追加的事件账本"
# 真实项目会写入对象存储 / 数仓（课 10 的日志管道拓扑用 Kafka Connect 干这事）
audit_log = []


def build_consumer():
    return KafkaConsumer(
        TOPIC_ORDERS,
        bootstrap_servers=BOOTSTRAP_SERVERS,
        group_id='audit-service',   # 第三个消费者组：与积分、风控完全独立
        auto_offset_reset='earliest',
        enable_auto_commit=False,
        value_deserializer=from_json_bytes,
    )


def main():
    consumer = build_consumer()
    log.info('审计服务启动，group=audit-service（与积分/风控互不干扰）')

    try:
        for msg in consumer:
            event = msg.value
            # 审计不做业务判断，只追加事实 —— 这就是事件溯源的核心思想
            audit_log.append({
                'event_id': event.get('event_id'),
                'event_type': event.get('event_type'),
                'user_id': event.get('user_id'),
                'partition': msg.partition,
                'offset': msg.offset,
            })
            log.info('留痕 #%d: %s（partition=%d offset=%d）',
                     len(audit_log), event.get('event_id'),
                     msg.partition, msg.offset)
            consumer.commit()
    except KafkaError as exc:
        log.error('Kafka 异常: %s', exc)
    finally:
        log.info('共留痕 %d 条事件', len(audit_log))
        consumer.close()


if __name__ == '__main__':
    main()
