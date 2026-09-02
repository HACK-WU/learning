#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
缓存层：Cache Aside 模式 + 三层防护（穿透 / 击穿 / 雪崩）

覆盖知识点：
  阶段1·课2 · key 设计        → 统一 cache:good:{id} 命名，便于按前缀统计与批量管理
  阶段2·课3 · Hash 存对象      → 商品对象用 Hash 存，支持部分读写（只改库存字段）
  阶段4·课8 · 缓存穿透         → 空值缓存 + 布隆式前置判断（此处用空值占位演示）
  阶段4·课8 · 缓存击穿         → 热点 key 用 SET NX 互斥重建，避免并发全部打到 DB
  阶段4·课8 · 缓存雪崩         → TTL 加随机抖动，避免同一秒集体失效
  阶段4·课8 · 一致性           → Cache Aside：先更库，再删缓存（不是更新缓存）
  阶段4·课9 · 安全基线         → 连接用 appuser，无法执行 KEYS/FLUSHALL

设计决策见 ../设计决策.md 决策 1（为何选 Cache Aside 而非 Write Through）
"""
import time
import random

from redislib import conn_master, conn_replica, RedisError

# ---------- 模拟数据库（真实项目里这里是 MySQL） ----------
class FakeDB:
    """模拟数据库：每次查询固定耗时，用于量化缓存的收益"""

    def __init__(self, latency_ms=20):
        self.latency_ms = latency_ms
        self.data = {}          # id -> dict
        self.query_count = 0    # 统计被打了多少次

    def get_good(self, good_id):
        self.query_count += 1
        time.sleep(self.latency_ms / 1000.0)   # 模拟磁盘 IO
        return self.data.get(good_id)

    def update_good(self, good_id, **fields):
        time.sleep(self.latency_ms / 1000.0)
        if good_id in self.data:
            self.data[good_id].update(fields)
            return True
        return False


DB = FakeDB(latency_ms=20)

# ---------- 缓存 key 规范（阶段1·课2） ----------
K_GOOD = 'cache:good:{gid}'          # 商品对象（Hash）
K_EMPTY = 'cache:empty:{gid}'        # 空值占位（防穿透）
K_LOCK = 'cache:lock:{gid}'          # 重建互斥锁（防击穿）

BASE_TTL = 300        # 基础过期 5 分钟
JITTER = 120          # 抖动 ±2 分钟（防雪崩）


def _ttl():
    """TTL 加随机抖动——雪崩防护的核心：不让这批 key 在同一秒集体失效"""
    return BASE_TTL + random.randint(0, JITTER)


def seed_goods(r, n=200):
    """预置商品数据到数据库（不进缓存，模拟冷启动）"""
    for i in range(1, n + 1):
        DB.data[i] = {
            'id': str(i),
            'name': '商品%d' % i,
            'price': str(10 + i % 90),
            'stock': str(1000),
        }
    print('  已预置 %d 个商品到数据库（缓存为空，模拟冷启动）' % n)


# ---------- 缓存读取：三层防护 ----------
def get_good(r, gid, use_lock=True):
    """
    Cache Aside 读路径，含穿透 + 击穿防护。

    返回 (数据 or None, 来源)  来源 ∈ {cache, db, empty_marker}
    """
    key = K_GOOD.format(gid=gid)
    empty_key = K_EMPTY.format(gid=gid)
    lock_key = K_LOCK.format(gid=gid)

    # 1) 先查缓存
    try:
        cached = r.cmd('HGETALL', key)
    except RedisError as e:
        # 缓存故障不能拖垮业务 —— 降级直接查库（阶段4·课8 缓存可用性取舍）
        print('    [降级] 缓存异常，直查数据库：%s' % e)
        return DB.get_good(gid), 'db'

    if cached and isinstance(cached, (list, tuple)):
        # RESP2 的 HGETALL 返回扁平数组 [field, value, field, value...]
        d = {}
        for i in range(0, len(cached), 2):
            k = cached[i].decode() if isinstance(cached[i], bytes) else cached[i]
            v = cached[i + 1].decode() if isinstance(cached[i + 1], bytes) else cached[i + 1]
            d[k] = v
        return d, 'cache'

    # 2) 缓存没有 → 查空值标记（防穿透：确认不存在的 id 不再打库）
    try:
        if r.cmd('EXISTS', empty_key):
            return None, 'empty_marker'
    except RedisError:
        pass

    # 3) 查数据库前先抢锁（防击穿：只让一个线程去重建）
    if use_lock:
        try:
            got = r.cmd('SET', lock_key, '1', 'NX', 'PX', 3000)
        except RedisError:
            got = None

        if not got:
            # 没抢到锁 —— 说明别人在重建。短暂等待后重读缓存，不打到数据库
            for _ in range(30):
                time.sleep(0.005)
                try:
                    cached = r.cmd('HGETALL', key)
                except RedisError:
                    cached = None
                if cached and isinstance(cached, (list, tuple)):
                    d = {}
                    for i in range(0, len(cached), 2):
                        k = cached[i].decode() if isinstance(cached[i], bytes) else cached[i]
                        v = cached[i + 1].decode() if isinstance(cached[i + 1], bytes) else cached[i + 1]
                        d[k] = v
                    return d, 'cache'
            # 等待超时，兜底查库
            return DB.get_good(gid), 'db'

    try:
        # 4) 抢到锁，查数据库
        row = DB.get_good(gid)
        if row is None:
            # 防穿透：数据库也没有 → 写空值标记，短 TTL
            try:
                r.cmd('SET', empty_key, '1', 'EX', 60)
            except RedisError:
                pass
            return None, 'db'

        # 5) 回写缓存。用 Hash 存（阶段2·课3），TTL 带抖动（防雪崩）
        try:
            r.cmd('HSET', key, *[x for kv in row.items() for x in kv])
            r.cmd('EXPIRE', key, _ttl())
        except RedisError:
            pass
        return row, 'db'
    finally:
        # 6) 释放锁
        try:
            r.cmd('DEL', lock_key)
        except RedisError:
            pass


# ---------- 缓存更新：Cache Aside 的一致性处理 ----------
def update_good(r, gid, **fields):
    """
    先更新数据库，再删除缓存。

    为什么是「删缓存」而不是「更新缓存」？
      - 更新缓存：并发写时可能把旧值写回（A 更库 → B 更库 → B 更新缓存 → A 更新缓存 = 脏数据）
      - 删缓存：  下次读时自然回源，最多一次回源开销，不会写脏
    详见 ../设计决策.md 决策 2
    """
    ok = DB.update_good(gid, **fields)
    if ok:
        try:
            r.cmd('DEL', K_GOOD.format(gid=gid))   # 删缓存，不是更新缓存
        except RedisError as e:
            # 删缓存失败必须处理 —— 否则数据库已更新而缓存仍是旧值，长期不一致
            print('    [严重] 删缓存失败，需补偿：%s' % e)
            return False
    return ok


def warmup(r, gids):
    """预热：大促开始前把热点商品灌进缓存，避免开抢瞬间全部回源"""
    cmds = []
    for gid in gids:
        row = DB.data.get(gid)
        if not row:
            continue
        key = K_GOOD.format(gid=gid)
        cmds.append(('HSET', key, *[x for kv in row.items() for x in kv]))
        cmds.append(('EXPIRE', key, _ttl()))
    r.pipeline(cmds)
    return len(gids)
