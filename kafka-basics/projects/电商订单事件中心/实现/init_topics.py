# init_topics.py：一次性初始化本项目需要的 topic
# 知识点回指：课 3（创建 topic）、课 4（分区与副本）、课 10（topic 三原则）

from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError

from common import (
    BOOTSTRAP_SERVERS, TOPIC_ORDERS, TOPIC_DLQ, TOPIC_RISK_RESULT,
    PARTITIONS, REPLICATION_FACTOR, setup_logging,
)

log = setup_logging('init-topics')


def main():
    admin = KafkaAdminClient(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        client_id='order-event-hub-admin',
    )

    topics = [
        # 主干：一个 topic 一类事件（课 10 原则 2），按业务事件命名（原则 1）
        NewTopic(TOPIC_ORDERS, num_partitions=PARTITIONS,
                 replication_factor=REPLICATION_FACTOR),
        # 死信队列：坏消息的出口，避免毒药消息阻塞主分区（设计决策 2）
        NewTopic(TOPIC_DLQ, num_partitions=1, replication_factor=REPLICATION_FACTOR),
        # 风控结果：风控服务事务写入的输出 topic
        NewTopic(TOPIC_RISK_RESULT, num_partitions=PARTITIONS,
                 replication_factor=REPLICATION_FACTOR),
    ]

    for t in topics:
        try:
            admin.create_topics([t])
            log.info('已创建 topic: %s（分区 %d）', t.name, t.num_partitions)
        except TopicAlreadyExistsError:
            log.info('topic 已存在，跳过: %s', t.name)

    log.info('初始化完成。当前 topic 列表：%s', sorted(admin.list_topics()))
    admin.close()


if __name__ == '__main__':
    main()
