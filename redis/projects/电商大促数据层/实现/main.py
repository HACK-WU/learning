#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
电商大促数据层 · 主程序

串起完整链路：冷启动 → 预热 → 大促读流量 → 秒杀扣库存 → 排行榜 → 诊断 → 安全校验

运行：
    cd /mnt/d/projects/learning/redis/projects/电商大促数据层/实现
    python3 main.py

对应知识点见各模块头部注释与 ../README.md 的知识点地图
"""
import sys
import time
import threading
import random

sys.path.insert(0, '.')   # 保证 python3 main.py 直接跑时 import 到同目录模块

from redislib import (conn_master, conn_replica, conn_readonly, conn_insecure,
                      RedisError, section, subsect, fmt_bytes)
from cache_layer import get_good, update_good, seed_goods, warmup, DB
from inventory import Inventory, RankBoard, DailyStats
from diagnostics import Diagnostics


def demo_cache_flow(r):
    """第一幕：缓存是怎么把数据库压力打下来的"""
    section('第一幕 · 冷启动与缓存收益')
    seed_goods(r, n=200)

    subsect('1.1 无缓存时：直接查数据库')
    DB.query_count = 0
    t0 = time.time()
    for gid in range(1, 101):
        DB.get_good(gid)
    dt = time.time() - t0
    print('  100 次查询耗时 %.3f 秒，数据库被查 %d 次' % (dt, DB.query_count))
    print('  → 平均单次 %.1f ms（模拟磁盘 IO 20ms）' % (dt / 100 * 1000))

    subsect('1.2 预热后：走缓存')
    warmup(r, range(1, 101))
    DB.query_count = 0
    t0 = time.time()
    hit = 0
    for gid in range(1, 101):
        row, src = get_good(r, gid)
        if src == 'cache':
            hit += 1
    dt = time.time() - t0
    print('  100 次查询耗时 %.3f 秒，命中缓存 %d 次，回源 %d 次' % (dt, hit, DB.query_count))
    print('  → 平均单次 %.3f ms' % (dt / 100 * 1000))
    if dt > 0:
        print('  >>> 提速约 %.0f 倍' % ((0.020 * 100) / dt))


def demo_three_defenses(r):
    """第二幕：穿透 / 击穿 / 雪崩 三层防护实测"""
    section('第二幕 · 缓存三大问题与防护实测')

    subsect('2.1 缓存穿透：查不存在的 id')
    print('  连续查 50 次不存在的商品 id=999999')
    DB.query_count = 0
    for _ in range(50):
        row, src = get_good(r, 999999)
        _ = src
    print('  数据库被查 %d 次（首次回源后写入空值标记，后续 49 次全部拦在缓存层）' % DB.query_count)
    if DB.query_count <= 1:
        print('  ✓ 穿透防护生效：数据库只被打了 %d 次' % DB.query_count)

    subsect('2.2 缓存击穿：热点 key 失效瞬间的并发冲击')
    hot_gid = 7
    # 先确保缓存里有
    warmup(r, [hot_gid])
    # 模拟缓存突然失效
    r.cmd('DEL', 'cache:good:%d' % hot_gid)
    DB.query_count = 0

    errors = []
    def concurrent_read(idx):
        # 每线程独立连接：RESP 是请求-响应严格配对的流式协议，
        # 共用连接会导致响应串位（本项目实测踩坑，见设计决策.md 决策 4）
        rr = conn_master()
        try:
            from cache_layer import get_good as _get
            _get(rr, hot_gid)
        except Exception as e:
            errors.append(str(e))
        finally:
            rr.close()

    threads = [threading.Thread(target=concurrent_read, args=(i,))
               for i in range(30)]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    dt = time.time() - t0
    print('  30 个线程同时请求刚失效的热点 key')
    print('  数据库被查 %d 次，耗时 %.3f 秒，异常 %d 个' % (DB.query_count, dt, len(errors)))
    if DB.query_count <= 1:
        print('  ✓ 击穿防护生效：30 个并发只回源 %d 次（互斥锁让其余线程等待并复用结果）'
              % DB.query_count)

    subsect('2.3 缓存雪崩：TTL 随机抖动验证')
    keys = r.cmd('SCAN', 0, 'MATCH', 'cache:good:*', 'COUNT', 1000)[1]
    ttls = []
    for k in keys[:20]:
        k = k.decode() if isinstance(k, bytes) else k
        ttl = r.cmd('TTL', k)
        if ttl and ttl > 0:
            ttls.append(ttl)
    if ttls:
        print('  抽查 %d 个商品 key 的剩余 TTL（秒）：' % len(ttls))
        print('    ', sorted(ttls))
        print('  最小 %d / 最大 %d / 跨度 %d 秒' % (min(ttls), max(ttls), max(ttls) - min(ttls)))
        print('  ✓ TTL 已分散，不会在同一秒集体失效（抖动范围 0~120 秒）')


def demo_consistency(r):
    """第三幕：缓存与数据库一致性"""
    section('第三幕 · 一致性：更新时为什么删缓存而不是更新缓存')

    gid = 42
    warmup(r, [gid])
    before, _ = get_good(r, gid)
    print('  更新前，缓存中的价格：%s' % (before or {}).get('price'))

    subsect('3.1 先更库、再删缓存（Cache Aside 正确顺序）')
    ok = update_good(r, gid, price='999')
    print('  数据库已更新为 price=999，缓存删除结果：%s' % ok)
    print('  缓存当前状态：%s' % ('已删除' if r.cmd('EXISTS', 'cache:good:%d' % gid) == 0 else '仍存在'))

    row, src = get_good(r, gid)
    print('  重新读取：来源=%s，价格=%s' % (src, (row or {}).get('price')))
    if (row or {}).get('price') == '999':
        print('  ✓ 一致：删除缓存后重新回源，读到新值')

    subsect('3.2 反面演示：如果只更新数据库不删缓存会怎样')
    warmup(r, [gid])
    DB.update_good(gid, price='888')     # 只改库，不动缓存
    row, src = get_good(r, gid)
    print('  数据库已是 888，但缓存仍返回：%s（来源=%s）' % ((row or {}).get('price'), src))
    print('  ✗ 这就是脏数据 —— 会一直持续到 key 自然过期')
    print('  → 修复：更新数据库后必须删缓存，见 update_good() 的实现')


def demo_inventory(r):
    """第四幕：秒杀扣库存，Lua 保证原子"""
    section('第四幕 · 秒杀扣库存：杜绝超卖')

    inv = Inventory(r)
    gid = 1001
    init_count = 100
    inv.init_stock(gid, init_count)
    r.cmd('DEL', 'inventory:buyers:%d' % gid)
    r.cmd('DEL', 'rank:sales')
    print('  初始化库存 %d，模拟 500 个用户并发抢购' % init_count)

    results = []
    lock = threading.Lock()

    def buyer(uid):
        # ⚠️ 关键点：RESP 协议是「请求-响应严格配对」的流式协议，
        #    一个 socket 同一时刻只能承载一个未完成的请求-响应对。
        #    多线程共用一个连接会让响应串位（A 线程读到 B 的返回值），
        #    所以每个线程必须建自己的连接（生产上用连接池）。
        rr = conn_master()
        try:
            ret = rr.cmd('EVAL', __import__('inventory').LUA_SECKILL, 2,
                         'inventory:stock:%d' % gid,
                         'inventory:buyers:%d' % gid,
                         str(uid), 'rank:sales', str(gid))
            with lock:
                results.append(ret)
        except Exception as e:
            with lock:
                results.append('ERR:%s' % str(e)[:50])
        finally:
            rr.close()

    threads = [threading.Thread(target=buyer, args=(i,)) for i in range(500)]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    dt = time.time() - t0

    # 统计口径：三类互斥，加起来必须等于线程数
    success = sum(1 for x in results if isinstance(x, int) and x >= 0)
    sold_out = sum(1 for x in results if x == -2)
    limited = sum(1 for x in results if x == -3)
    nokey = sum(1 for x in results if x == -1)
    errs = [x for x in results if isinstance(x, str)]

    print('  耗时 %.3f 秒' % dt)
    print('  下单成功 %d 人，售罄 %d 人，限购拦截 %d 人，异常 %d 个'
          % (success, sold_out, limited, len(errs)))
    print('  （分类合计 %d，应等于参与线程数 500）'
          % (success + sold_out + limited + nokey + len(errs)))
    left = inv.get_stock(gid)
    print('  最终剩余库存：%d' % left)
    print('  成功数 + 剩余 = %d（初始 %d）' % (success + left, init_count))

    if success + left == init_count and left >= 0:
        print('  ✓ 无超卖：成功数与剩余库存账目完全对平，库存未变负')
    else:
        print('  ✗ 账目不平，存在超卖！')

    subsect('4.1 排行榜（ZSet）')
    board = RankBoard(r)
    print('  排行榜商品数：%d' % board.size())
    print('  Top5 销量：')
    for m, s in board.top(5):
        print('    %-10s %.0f' % (m, s))

    subsect('4.2 日统计（Hash 原子累加）')
    st = DailyStats(r)
    for _ in range(50):
        st.incr('pv')
    st.incr('orders', success)
    print('  当日统计：%s' % st.all())


def demo_diagnostics(r):
    """第五幕：把课 9 的诊断能力用起来"""
    section('第五幕 · 诊断：出问题了怎么查')

    d = Diagnostics(r)
    subsect('5.1 整体指标')
    d.print_overview()

    subsect('5.2 命令维度统计')
    d.print_command_stats(top=8)

    subsect('5.3 慢查询日志（阈值 %d 微秒）' % d.slowlog_threshold())
    d.print_slowlog(n=5)
    print('  ⚠️ 注意：SLOWLOG 只记录命令在 Redis 内的执行耗时，不含网络传输与客户端排队。')
    print('     所以"慢查询为空"不等于"用户没觉得慢"。')

    subsect('5.4 大 key 扫描')
    d.print_big_keys(top=6)

    subsect('5.5 热 key 识别')
    hk, policy = d.hot_keys(top=6)
    if hk is None:
        print('  当前淘汰策略为 %s，非 LFU 系列 → OBJECT FREQ 不可用' % policy)
        print('  这是预期行为：LFU 计数器只在 LFU 策略下维护。')
        print('  → 生产上要识别热 key，可临时切到 allkeys-lfu，或用客户端/代理层采样统计。')
    else:
        print('  策略 %s，Top 热 key：' % policy)
        for k, f in hk:
            print('    %-40s freq=%d' % (k[:40], f))

    subsect('5.6 延迟监控')
    th = d.latency_monitor_threshold()
    print('  latency-monitor-threshold = %d' % th)
    if th == 0:
        print('  ⚠️ 默认 0 = 关闭！出厂默认不监控延迟，出问题后无从回溯。')
    else:
        print('  ✓ 已开启，超过 %d 毫秒的事件会被记录' % th)
    ev = d.latency_events()
    print('  当前延迟事件：%s' % (ev if ev else '（无）'))


def demo_security(r):
    """第六幕：安全基线校验"""
    section('第六幕 · 安全基线：默认配置等于裸奔')

    subsect('6.1 加固后的主库（7201）')
    print('  用最小权限账号连接，逐个验证权限边界：')
    ro = conn_readonly()
    checks = [
        ('readonly 读 cache:good:1', lambda: ro.cmd('EXISTS', 'cache:good:1')),
        ('readonly 写（应被拒）', lambda: ro.cmd('SET', 'cache:evil', '1')),
    ]
    for name, fn in checks:
        try:
            v = fn()
            print('    %-28s → %s' % (name, v))
        except RedisError as e:
            print('    %-28s → 被拒绝：%s' % (name, str(e)[:60]))

    print('  appuser 的危险命令验证：')
    for name, c in [('KEYS *', ('KEYS', '*')),
                    ('FLUSHALL', ('FLUSHALL',)),
                    ('DEBUG SLEEP', ('DEBUG', 'SLEEP', '1'))]:
        try:
            r.cmd(*c)
            print('    %-28s → 可执行（危险！）' % name)
        except RedisError as e:
            print('    %-28s → 被拒绝：%s' % (name, str(e)[:50]))

    subsect('6.2 出厂默认的反例实例（7203）')
    bad = conn_insecure()
    print('  无任何认证，任意连接可以：')
    for name, c in [('写入任意 key', ('SET', 'attacker:owned', '1')),
                    ('读取全部数据', ('DBSIZE',)),
                    ('执行 FLUSHALL', ('FLUSHALL',))]:
        try:
            v = bad.cmd(*c)
            print('    %-20s → %s' % (name, v))
        except RedisError as e:
            print('    %-20s → %s' % (name, e))
    print('  ✗ 这就是出厂默认：user default on nopass ~* +@all')


def demo_replica():
    """第七幕：读写分离与复制延迟"""
    section('第七幕 · 读写分离：从库能读到什么')

    r = conn_master()
    ro = conn_replica()
    r.cmd('SET', 'cache:replica:probe', 'v-%d' % int(time.time()))
    time.sleep(0.5)
    v = ro.cmd('GET', 'cache:replica:probe')
    print('  主库写入后，从库读到：%s' % v)

    try:
        ro.cmd('SET', 'cache:write:to:replica', '1')
        print('  ✗ 从库竟然可写！')
    except RedisError as e:
        print('  从库写入被拒：%s' % str(e)[:60])
        print('  ✓ 从库只读，符合预期（replica-read-only 默认 yes）')


def main():
    r = conn_master()
    ver = r.cmd('INFO', 'server')
    if isinstance(ver, bytes):
        ver = ver.decode()
    line = [x for x in ver.splitlines() if x.startswith('redis_version:')]
    print('=' * 70)
    print('  结课实战项目 · 电商大促数据层')
    print('  Redis %s' % (line[0].split(':', 1)[1].strip() if line else 'unknown'))
    print('=' * 70)
    # 从一个干净的实验库开始
    demo_cache_flow(r)
    demo_three_defenses(r)
    demo_consistency(r)
    demo_inventory(r)
    demo_diagnostics(r)
    demo_security(r)
    demo_replica()

    section('全部演示完成')
    print('  接下来：对照 ../验收清单.md 逐项自测，')
    print('          对照 ../设计决策.md 理解每个选型为什么这么做，')
    print('          对照 ../反例对照.md 看"能跑但很糟"的写法错在哪。')


if __name__ == '__main__':
    main()
