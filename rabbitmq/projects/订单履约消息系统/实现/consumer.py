# -*- coding: utf-8 -*-
"""消费者基类：手动 ack + 重试语义 + 幂等接入

知识点对照：
- 课 6：消费者确认 —— 必须 auto_ack=False，auto_ack 下 prefetch 完全无效
- 课 10：nack 与 reject 在 4.3 **不再等价**（本项目探测确认）
- 课 8：幂等 —— 至少一次语义下必须做
- 课 6：prefetch —— 不设会导致先连上的消费者抢空队列

⚠️ 本项目最重要的一个决策（决策 3）：
    **业务失败一律用 reject，不用 nack。**
    原因：延迟退避与 delivery-limit 都只看 delivery-count，
    而 delivery-count 只在"投递失败"时递增 —— 只有 reject 算失败。
    用 nack 重试 → 计数不涨 → 延迟恒定 → 永远够不到 delivery-limit
    → 消息在队列里**无限循环**，永不进死信。
    实测（p3-probe-retry3.py）：
      reject → 间隔 1.04/2.09/3.02s，超限进死信 ✓
      nack   → 间隔恒 1.04s，6 轮后仍在队列，死信为空 ✗
"""
import json
import logging

import pika

logger = logging.getLogger(__name__)


class BaseConsumer:
    """消费者基类：把"消息处理"与"消息协议的坑"分离开。

    子类只需实现 handle(body, props) 返回 True/False，
    协议层的 ack/reject/幂等/重试由基类统一处理。
    这是"可维护性"约束的一部分：业务代码不该关心 4.3 的 nack/reject 差异。

    两种重试模式（由 broker_managed_retry 决定）：
      True（默认，用于 quorum 队列）：
         失败 → reject(requeue=True)，由 broker 的 x-delayed-retry-* 做退避，
         累计失败达 x-delivery-limit 后自动转死信。**计数交给 broker。**
      False（用于 classic 队列）：
         classic 不接受 x-delivery-limit 与 x-delayed-retry-*（本项目实测），
         必须由应用自己数重试次数，超限后 requeue=False 直接送死信。
         **计数在应用层，靠消息头 x-app-retry-count 传递。**
    """

    #: 应用层重试上限（仅 broker_managed_retry=False 时生效）
    APP_MAX_RETRY = 3

    def __init__(self, mgr, queue, step_name, idempotency_store,
                 prefetch=10, auto_ack=False, broker_managed_retry=True):
        self.mgr = mgr
        self.queue = queue
        self.step_name = step_name
        self.store = idempotency_store
        self.prefetch = prefetch
        self.auto_ack = auto_ack
        self.ch = None
        self._stopped = False
        self.broker_managed_retry = broker_managed_retry
        self.stats = {'processed': 0, 'skipped': 0, 'failed': 0, 'dead': 0}

    def start(self):
        """启动消费（阻塞）。"""
        self.ch = self.mgr.get_channel()
        # 课 6：prefetch 必须在消费前设置，且**只对 auto_ack=False 有效**
        self.ch.basic_qos(prefetch_count=self.prefetch)
        logger.info('[%s] 开始消费 %s（prefetch=%d）',
                    self.step_name, self.queue, self.prefetch)

        self.ch.basic_consume(queue=self.queue,
                              on_message_callback=self._on_message,
                              auto_ack=self.auto_ack)
        try:
            self.ch.start_consuming()
        except KeyboardInterrupt:
            logger.info('[%s] 收到中断信号，停止消费', self.step_name)
            self.stop()

    def stop(self):
        self._stopped = True
        if self.ch and self.ch.is_open:
            try:
                self.ch.stop_consuming()
            except Exception:  # noqa: BLE001
                pass

    def _on_message(self, ch, method, props, body):
        """统一的消息入口：幂等 → 业务处理 → ack/reject。"""
        try:
            data = json.loads(body)
        except Exception as e:  # noqa: BLE001
            # 消息体本身是坏的 —— 重试也没用，直接 reject 让它进死信
            logger.error('[%s] 消息体解析失败，直接进死信：%s',
                         self.step_name, e)
            ch.basic_reject(delivery_tag=method.delivery_tag, requeue=False)
            self.stats['failed'] += 1
            return

        order_id = data.get('order_id', 'UNKNOWN')
        key = f"{order_id}:{self.step_name}"

        # ---- 第 1 步：幂等抢占（课 8）----
        # 注意：redelivered **不能**用来判断重复（课 8 实测生产侧重复时它是 False）
        if not self.store.acquire(key):
            ch.basic_ack(delivery_tag=method.delivery_tag)
            self.stats['skipped'] += 1
            return

        # ---- 第 2 步：业务处理 ----
        try:
            ok = self.handle(data, props)
        except Exception as e:  # noqa: BLE001
            logger.error('[%s] 业务异常：%s', self.step_name, e)
            ok = False

        # ---- 第 3 步：按结果决定 ack / reject / 释放 ----
        if ok:
            # 成功：确认幂等 + ack
            self.store.mark_done(key)
            ch.basic_ack(delivery_tag=method.delivery_tag)
            self.stats['processed'] += 1
            logger.info('[%s] ✓ 处理成功：%s', self.step_name, order_id)
            return

        # ---- 失败分支 ----
        # 释放幂等锁（允许重来）
        self.store.release(key)
        self.stats['failed'] += 1

        if self.broker_managed_retry:
            # quorum 队列：交给 broker。
            # ⚠️ 决策 3：必须用 reject，不能用 nack。
            # reject 会推进 delivery-count → 延迟退避递增 → 达到
            # x-delivery-limit 后 broker 自动转死信。
            ch.basic_reject(delivery_tag=method.delivery_tag, requeue=True)
            logger.warning(
                '[%s] ✗ 失败，reject 触发 broker 重试：%s'
                '（delivery-count +1，达上限转死信）',
                self.step_name, order_id)
        else:
            # classic 队列：broker 不做退避也不计数，全靠应用自己。
            # 课 6 教训：requeue=True 不写 x-death，不能用它计数。
            # 所以自维护一个 x-app-retry-count 头，重发时 +1。
            headers = dict(props.headers or {})
            count = int(headers.get('x-app-retry-count', 0)) + 1

            if count > self.APP_MAX_RETRY:
                # 超限：requeue=False 直接送死信（这是唯一让 classic 进死信的办法）
                ch.basic_reject(delivery_tag=method.delivery_tag,
                                requeue=False)
                self.stats['dead'] += 1
                logger.error(
                    '[%s] ☠ 重试 %d 次仍失败，送死信：%s',
                    self.step_name, count - 1, order_id)
                return

            # 未超限：重发一条带递增计数的新消息，然后 ack 旧的
            # （课 10 方法学教训：ack + 重发会让计数归零，所以计数必须放在消息里）
            headers['x-app-retry-count'] = count
            ch.basic_publish(
                exchange=method.exchange or '',
                routing_key=method.routing_key,
                body=body,
                properties=pika.BasicProperties(
                    delivery_mode=2,
                    content_type=props.content_type,
                    message_id=props.message_id,
                    headers=headers,
                ),
            )
            ch.basic_ack(delivery_tag=method.delivery_tag)
            logger.warning(
                '[%s] ✗ 失败，应用层重投（第 %d/%d 次）：%s',
                self.step_name, count, self.APP_MAX_RETRY, order_id)

    def handle(self, data, props):
        """业务处理，子类实现。返回 True=成功，False=失败（会触发重试）。"""
        raise NotImplementedError
