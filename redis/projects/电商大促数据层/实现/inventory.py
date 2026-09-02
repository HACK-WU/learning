#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
库存与排行榜：Lua 原子扣减 + ZSet 实时排行

覆盖知识点：
  阶段2·课4 · ZSet 跳表+哈希表双结构  → 销量排行榜用 ZSet，O(logN) 更新与取 TopN
  阶段2·课3 · Hash 存对象              → Hash 的 HINCRBY 做原子字段增减，避免整对象读改写
  阶段4·课7 · Lua 脚本                 → 扣库存用 Lua 保证「判断+扣减」原子，杜绝超卖
  阶段4·课7 · 集群下 Lua 的 key 限制   → 脚本只用单 key，天然满足同槽要求（EVAL 时声明 1 个 key）
  阶段4·课9 · 性能诊断                 → 脚本内避免 KEYS / 大范围遍历

库存扣减为什么必须用 Lua？
  写成 GET → 判断 → DECR 三步，高并发下两个请求同时读到 stock=1，都会判定"够"，
  然后各扣一次变成 -1，这就是超卖。Lua 在 Redis 里单线程执行，整段逻辑不可分割。
"""

from redislib import conn_master, RedisError

K_STOCK = 'inventory:stock:{gid}'      # 库存计数（String，Lua 内 DECR）
K_RANK = 'rank:sales'                   # 销量排行（ZSet）
K_STATS = 'stats:daily:{day}'           # 日统计（Hash）

# 扣库存 Lua 脚本：判断 + 扣减 + 记录，一次原子完成
#
# ⚠️ 返回值设计（本项目的一个真实踩坑）：
#   初版用 0 同时表示「扣减成功但扣完剩 0」和「库存不足，扣减失败」，
#   两者业务处理完全不同（要发券 vs 要提示售罄），调用方却无法区分。
#   改进版用 -2 明确表示失败，0 只表示「扣完剩 0」，歧义消除。
#   详见 ../设计决策.md 决策 3
LUA_DEDUCT = """
-- KEYS[1] = 库存 key
-- ARGV[1] = 扣减数量
-- ARGV[2] = 商品 id（用于写排行榜）
-- ARGV[3] = 排行榜 key
-- 返回： >=0 成功（扣减后剩余） | -1 key 不存在 | -2 库存不足
local stock = tonumber(redis.call('GET', KEYS[1]))
if stock == nil then
    return -1          -- 库存 key 不存在，异常
end
local need = tonumber(ARGV[1])
if stock < need then
    return -2          -- 库存不足，扣减失败
end
redis.call('DECRBY', KEYS[1], need)
-- 同步累加销量排行榜（ZSet，阶段2·课4）
redis.call('ZINCRBY', ARGV[3], need, ARGV[2])
return stock - need    -- 返回扣减后剩余（可能为 0，表示最后一个被抢到）
"""

# 秒杀场景的「限购」脚本：一人一单，用 Set 去重 + 库存扣减一起原子化
# 返回值： >=0 成功（剩余） | -1 key 不存在 | -2 库存不足 | -3 已购买过
LUA_SECKILL = """
-- KEYS[1] = 库存 key
-- KEYS[2] = 已购用户 Set
-- ARGV[1] = 用户 id
-- ARGV[2] = 排行榜 key
-- ARGV[3] = 商品 id
local stock = tonumber(redis.call('GET', KEYS[1]))
if stock == nil then return -1 end
if stock <= 0 then return -2 end
-- 限购判定：已买过直接拒绝（阶段2·课4 Set 去重）
if redis.call('SISMEMBER', KEYS[2], ARGV[1]) == 1 then
    return -3
end
redis.call('DECRBY', KEYS[1], 1)
redis.call('SADD', KEYS[2], ARGV[1])
redis.call('ZINCRBY', ARGV[2], 1, ARGV[3])
return stock - 1
"""


class Inventory:
    def __init__(self, r):
        self.r = r

    def init_stock(self, gid, count):
        """初始化库存。真实场景要设合理上限，避免误设成超大值"""
        return self.r.cmd('SET', K_STOCK.format(gid=gid), count)

    def get_stock(self, gid):
        v = self.r.cmd('GET', K_STOCK.format(gid=gid))
        return int(v) if v is not None else None

    def deduct(self, gid, n=1, rank=True):
        """
        原子扣减库存。返回值：
          >=0  扣减成功，返回扣减后剩余库存（0 表示最后一个被抢到）
          -1   库存 key 不存在
          -2   库存不足，扣减失败
        """
        return self.r.cmd('EVAL', LUA_DEDUCT, 1,
                          K_STOCK.format(gid=gid),
                          n, str(gid), K_RANK)

    def seckill(self, gid, uid):
        """
        秒杀下单：库存扣减 + 一人一单限购，原子完成。返回值：
          >=0  下单成功，返回剩余库存（0 表示最后一个被抢到）
          -1   库存 key 不存在
          -2   已售罄，扣减失败
          -3   该用户已购买过（限购生效）
        """
        return self.r.cmd('EVAL', LUA_SECKILL, 2,
                          K_STOCK.format(gid=gid),
                          'inventory:buyers:%s' % gid,
                          str(uid), K_RANK, str(gid))


class RankBoard:
    """销量排行榜（ZSet）"""

    def __init__(self, r):
        self.r = r

    def top(self, n=10, withscores=True):
        """取 TopN。ZREVRANGE 按 score 倒序，O(logN + M)"""
        if withscores:
            raw = self.r.cmd('ZREVRANGE', K_RANK, 0, n - 1, 'WITHSCORES')
            out = []
            for i in range(0, len(raw), 2):
                m = raw[i]
                m = m.decode() if isinstance(m, bytes) else m
                out.append((m, float(raw[i + 1])))
            return out
        return self.r.cmd('ZREVRANGE', K_RANK, 0, n - 1)

    def rank_of(self, gid):
        """查某个商品的排名（从 0 开始）。ZREVRANK O(logN)"""
        v = self.r.cmd('ZREVRANK', K_RANK, str(gid))
        return v

    def size(self):
        return self.r.cmd('ZCARD', K_RANK)


class DailyStats:
    """日统计：用 Hash 的 HINCRBY 做原子计数，避免整对象读改写（阶段2·课3）"""

    def __init__(self, r, day=None):
        self.r = r
        self.day = day or time.strftime('%Y%m%d')
        self.key = K_STATS.format(day=self.day)

    def incr(self, field, n=1):
        """原子累加某个字段。HINCRBY 是原子操作，并发安全"""
        return self.r.cmd('HINCRBY', self.key, field, n)

    def all(self):
        raw = self.r.cmd('HGETALL', self.key)
        if not raw:
            return {}
        d = {}
        for i in range(0, len(raw), 2):
            k = raw[i].decode() if isinstance(raw[i], bytes) else raw[i]
            v = raw[i + 1].decode() if isinstance(raw[i + 1], bytes) else raw[i + 1]
            d[k] = int(v) if v.lstrip('-').isdigit() else v
        return d


# 让模块内的 time.strftime 可用
import time  # noqa: E402  放在末尾避免与上面的 docstring 冲突说明
