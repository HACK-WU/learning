# -*- coding: utf-8 -*-
"""连接工厂：带自动重连的连接管理

知识点对照（课 9：Python 客户端工程实践）：
- 连接是重资源（实测 4.50 ms/个），信道很轻（0.53 ms/个），差 8.6 倍
  → 一个进程复用一个连接，每个消费者用独立信道
- 心跳：pika 是"客户端值优先"（与主流教程说的"取较小值"相反）
- 重连：捕获 AMQPConnectionError 后退避重试
- ⚠️ 一条连接/信道不要跨线程同时使用（课 9 实测会抛 StreamLostError）

本项目简化：单线程顺序执行，不跨线程共享连接。
"""
import logging
import time

import pika
from pika.exceptions import AMQPConnectionError, AMQPChannelError

from config import NODES, USER, PASS, VHOST, HEARTBEAT, BLOCKED_TIMEOUT

logger = logging.getLogger(__name__)


class ConnectionManager:
    """管理一条长连接，断线后自动重连。

    为什么不用 pika 自带的自动重连：
    pika 的 BlockingConnection 没有内置重连，需要自己实现。
    生产环境更推荐用 SelectConnection + 事件循环，但那会显著增加代码复杂度，
    本项目为了可读性选择 BlockingConnection + 手工重连。
    """

    def __init__(self, max_retries=5, retry_delay=2):
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self._conn = None
        self._node_index = 0

    def _connect_one(self, host, port):
        """连单个节点。"""
        return pika.BlockingConnection(pika.ConnectionParameters(
            host=host,
            port=port,
            virtual_host=VHOST,
            credentials=pika.PlainCredentials(USER, PASS),
            heartbeat=HEARTBEAT,
            blocked_connection_timeout=BLOCKED_TIMEOUT,
        ))

    def connect(self):
        """建立连接，失败时依次尝试其他节点（课 11：任一节点都可用）。"""
        last_err = None
        # 从上次成功的节点开始，失败则轮询下一个
        for i in range(len(NODES)):
            host, port = NODES[(self._node_index + i) % len(NODES)]
            try:
                conn = self._connect_one(host, port)
                self._node_index = (self._node_index + i) % len(NODES)
                logger.info('已连接到 %s:%s', host, port)
                return conn
            except Exception as e:  # noqa: BLE001
                last_err = e
                logger.warning('连接 %s:%s 失败：%s，尝试下一个节点', host, port, e)
        raise AMQPConnectionError(f'所有节点均不可达：{last_err}')

    def get_connection(self):
        """获取当前连接（惰性建立）。"""
        if self._conn is None or self._conn.is_closed:
            self._conn = self.connect()
        return self._conn

    def get_channel(self, **kwargs):
        """在当前连接上开一个信道。

        课 9：信道是轻资源，但**不能跨线程共用**。
        """
        conn = self.get_connection()
        try:
            return conn.channel(**kwargs)
        except (AMQPConnectionError, AMQPChannelError):
            # 连接已死，重连后重试一次
            logger.warning('开信道失败，重连后重试')
            self._conn = self.connect()
            return self._conn.channel(**kwargs)

    def execute(self, func, *args, **kwargs):
        """带重连地执行一个操作。

        用法：
            mgr.execute(lambda ch: ch.basic_publish(...))
        当操作因连接断开而失败时，重连后重试最多 max_retries 次。
        """
        last_err = None
        for attempt in range(1, self.max_retries + 1):
            try:
                return func(*args, **kwargs)
            except (AMQPConnectionError, AMQPChannelError) as e:
                last_err = e
                logger.warning('第 %d/%d 次尝试失败：%s，%ds 后重连',
                               attempt, self.max_retries, e, self.retry_delay)
                time.sleep(self.retry_delay)
                self._conn = self.connect()
        raise last_err

    def close(self):
        if self._conn and not self._conn.is_closed:
            try:
                self._conn.close()
            except Exception:  # noqa: BLE001
                pass
        self._conn = None


def setup_logging(level=logging.INFO):
    """统一日志格式，方便按 order_id 追踪。"""
    logging.basicConfig(
        level=level,
        format='%(asctime)s [%(levelname)s] %(message)s',
        datefmt='%H:%M:%S',
    )
