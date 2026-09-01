# -*- coding: utf-8 -*-
"""幂等：去重表

知识点对照（课 8：交付语义与幂等）：
- 至少一次语义必然产生重复，重复有两个来源：
    ① 生产侧重复（生产者超时重发）→ redelivered = **False**（broker 不认识这是重复）
    ② 消费侧重复（崩溃重投 / requeue）→ redelivered = True
- 实测结论（课 8）：**redelivered 只能识别消费侧重复**，
  生产侧重复的 redelivered 序列是 [False, False] —— 看起来像两条全新的消息。
  → 必须靠业务单号（幂等键）识别，不能依赖 redelivered。

生产环境应把去重表换成 Redis（SETNX + 过期）或数据库唯一索引，
这里用内存 dict + 文件持久化模拟，便于单机演示。
"""
import json
import logging
import os
import threading

logger = logging.getLogger(__name__)


class IdempotencyStore:
    """幂等去重表：记录"已成功处理"的幂等键。

    三个方法对应三个时机：
    - check_and_mark：处理**前**抢占（防并发重复）
    - mark_done：处理**成功**后确认
    - release：处理**失败**后释放（允许重试）

    ⚠️ 为什么要分抢占/确认两步：
    如果只用"处理前记录"，那么处理到一半崩溃时，这条消息已被标记为已处理，
    重投后会被直接跳过 → **消息丢失**。
    必须"处理成功才最终确认"，失败则释放让它可以重来。
    """

    def __init__(self, persist_path=None):
        self._lock = threading.Lock()
        self._done = set()       # 已成功处理
        self._inflight = set()   # 处理中（抢占未确认）
        self._persist_path = persist_path
        if persist_path and os.path.exists(persist_path):
            self._load()

    def _load(self):
        try:
            with open(self._persist_path, 'r', encoding='utf-8') as f:
                self._done = set(json.load(f))
            logger.info('已从 %s 载入 %d 条去重记录',
                        self._persist_path, len(self._done))
        except Exception as e:  # noqa: BLE001
            logger.warning('载入去重表失败：%s', e)

    def _save(self):
        if not self._persist_path:
            return
        try:
            with open(self._persist_path, 'w', encoding='utf-8') as f:
                json.dump(sorted(self._done), f)
        except Exception as e:  # noqa: BLE001
            logger.warning('持久化去重表失败：%s', e)

    def is_done(self, key):
        """这条是否已经成功处理过。"""
        with self._lock:
            return key in self._done

    def acquire(self, key):
        """处理前抢占。返回 False 表示已被别人处理/正在处理，应跳过。"""
        with self._lock:
            if key in self._done:
                logger.info('幂等命中（已完成）：%s → 跳过', key)
                return False
            if key in self._inflight:
                logger.info('幂等命中（处理中）：%s → 跳过', key)
                return False
            self._inflight.add(key)
            return True

    def mark_done(self, key):
        """处理成功后确认。"""
        with self._lock:
            self._inflight.discard(key)
            self._done.add(key)
            self._save()

    def release(self, key):
        """处理失败后释放，允许重试。"""
        with self._lock:
            self._inflight.discard(key)

    def stats(self):
        with self._lock:
            return {'done': len(self._done), 'inflight': len(self._inflight)}


def make_idempotency_key(order_id, step):
    """构造幂等键。

    为什么是 order_id + step 而不是只用一个：
    同一个订单的"扣库存""发货""发短信"是三次独立的业务操作，
    各自需要独立幂等。若只用 order_id，扣库存成功后发货会被误判为已完成。
    """
    return f'{order_id}:{step}'


def demo_idempotency():
    """演示：重复投递被挡住。"""
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s [%(levelname)s] %(message)s')
    store = IdempotencyStore()
    key = make_idempotency_key('ORD-001', 'deduct_stock')

    print('=== 幂等演示 ===')
    print('场景：同一条消息被投递 3 次（模拟生产侧重复 + 消费侧重投）')
    print()

    executed = 0
    for i in range(1, 4):
        if store.acquire(key):
            executed += 1
            print(f'  第 {i} 次：抢占成功 → 执行业务（累计执行 {executed} 次）')
            store.mark_done(key)
        else:
            print(f'  第 {i} 次：幂等命中 → 跳过业务（累计执行 {executed} 次）')

    print()
    print(f'结果：投递 3 次，业务只执行 {executed} 次 → 幂等生效')
    print()
    print('=== 失败释放演示 ===')
    key2 = make_idempotency_key('ORD-002', 'deduct_stock')
    store.acquire(key2)
    print('  第 1 次：抢占成功 → 业务抛异常')
    store.release(key2)  # 关键：失败要释放，否则这条消息永远不会被重试
    if store.acquire(key2):
        print('  第 2 次：抢占成功（因为上次已释放）→ 可以重试 ✓')
        store.mark_done(key2)
    else:
        print('  第 2 次：抢占失败 ✗ 这就是"失败后不释放"导致消息丢失的后果')


if __name__ == '__main__':
    demo_idempotency()
