# common.py：公共配置
# 知识点回指：课 4（topic 与分区）、课 9（生产者/消费者基础配置）

import json
import logging

BOOTSTRAP_SERVERS = ['localhost:9092']

TOPIC_ORDERS = 'orders'          # 订单事件主干（课 10：按业务事件命名，不按消费方）
TOPIC_DLQ = 'orders.DLQ'         # 死信队列：反复处理失败的消息
TOPIC_RISK_RESULT = 'risk.result'  # 风控判定结果（风控事务的输出）

# 分区数 = 并行度上限（课 4/课 6）：消费者实例数超过分区数的部分会闲置
PARTITIONS = 3
REPLICATION_FACTOR = 1  # 单机 Docker 只能为 1；生产建议 3

MAX_RETRY = 3  # 失败重试次数，超过则进 DLQ（设计决策 2）


def setup_logging(name):
    # Windows 控制台默认 GBK，避免编码报错
    import sys
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(
        '%(asctime)s [%(name)s] %(levelname)s: %(message)s'
    ))
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        logger.addHandler(handler)
    return logger


def to_json_bytes(obj):
    return json.dumps(obj, ensure_ascii=False).encode('utf-8')


def from_json_bytes(data):
    return json.loads(data.decode('utf-8'))
