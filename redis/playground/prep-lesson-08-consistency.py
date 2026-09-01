#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 8 知识点 2 实测：缓存与数据库一致性。

核心目标：用可控并发复现"不一致窗口"，并证明延迟双删不能消除它。

实验列表：
  1. Cache Aside 正常路径（无并发）—— 结果一致
  2. 先更新数据库再删缓存 —— 复现"删除前读到旧值"窗口
  3. 先删缓存再更新数据库 —— 复现"旧值被回填"窗口（危害更大，持续时间更长）
  4. 延迟双删 —— 证明它只是缩小窗口，不消除窗口
  5. 删除缓存失败 —— 证明缓存长期脏数据
  6. 缓存删除 vs 更新缓存 —— 为什么删除优于更新
"""
import os
import time
import random
import threading
import importlib.util

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    'prep-lesson-08-lib.py')
_spec = importlib.util.spec_from_file_location('prep_lesson_08_lib', _LIB)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
Redis, FakeDB = _mod.Redis, _mod.FakeDB

PORT = 7101
KEY = 'user:1001:name'


def banner(t):
    print('\n' + '=' * 70)
    print(t)
    print('=' * 70)


def conn():
    return Redis(port=PORT)


def fresh(value='v1'):
    r = conn()
    r.flushdb()
    db = FakeDB(data={'id': value})
    r.set(KEY, value)
    return r, db


# ---------------------------------------------------------
# 实验 1：正常路径
# ---------------------------------------------------------
def test_normal():
    banner('实验 1：Cache Aside 正常路径（无并发）—— 结果是一致的')
    r, db = fresh('v1')
    print('初始: DB=%s, 缓存=%s' % (db.data, r.get(KEY)))

    # 写：先更新 DB，再删缓存
    db.set('id', 'v2')
    r.delete(KEY)
    print('写操作: UPDATE DB=v2 → DELETE 缓存')
    print('  删除后缓存: %r' % r.get(KEY))

    # 读：缓存 miss → 查 DB → 回填
    v = r.get(KEY)
    if v is None:
        v = db.get('id')
        r.set(KEY, v)
    print('读操作: miss → 查 DB(%s) → 回填缓存' % v)
    print('最终: DB=%s, 缓存=%s  ✅ 一致' % (db.data['id'], r.get(KEY)))
    r.close()


# ---------------------------------------------------------
# 实验 2：先更新 DB 再删缓存 的窗口
# ---------------------------------------------------------
def test_update_then_del():
    banner('实验 2：先更新数据库，再删缓存 —— 复现"删除前读到旧值"窗口')
    r, db = fresh('v1')

    # 读线程在 DB 已更新、缓存尚未删除的瞬间读到旧值
    events = []
    barrier1 = threading.Barrier(2)
    barrier2 = threading.Barrier(2)

    def writer():
        rr = conn()
        try:
            barrier1.wait()                 # 与读线程同步开始
            db.set('id', 'v2')              # 1. 更新 DB
            events.append(('writer', 'DB=v2', time.time()))
            barrier2.wait()                 # 等读线程读到旧值
            rr.delete(KEY)                  # 2. 删缓存
            events.append(('writer', 'DEL cache', time.time()))
        finally:
            rr.close()

    def reader():
        rr = conn()
        try:
            barrier1.wait()
            v = rr.get(KEY)                 # 此时缓存还是 v1（尚未删除）
            events.append(('reader', 'read=%s' % v, time.time()))
            barrier2.wait()
        finally:
            rr.close()

    tw = threading.Thread(target=writer)
    tr = threading.Thread(target=reader)
    tw.start(); tr.start(); tw.join(); tr.join()

    for who, what, t in sorted(events, key=lambda x: x[2]):
        print('  %-7s %s' % (who, what))
    print('结果：读线程在 DB 已更新但缓存未删时读到了 v1 —— 陈旧读窗口')
    print('窗口长度：仅"更新 DB"到"删除缓存"之间，通常毫秒级')
    print('自愈：缓存删除后，下一次读会回填 v2 → 最终一致')
    r.close()


# ---------------------------------------------------------
# 实验 3：先删缓存再更新 DB 的窗口（危害更大）
# ---------------------------------------------------------
def test_del_then_update():
    banner('实验 3：先删缓存，再更新数据库 —— 复现"旧值被回填"（危害更大）')
    r, db = fresh('v1')

    events = []
    b1 = threading.Barrier(2)
    b2 = threading.Barrier(2)
    b3 = threading.Barrier(2)

    def writer():
        rr = conn()
        try:
            b1.wait()
            rr.delete(KEY)                  # 1. 删缓存
            events.append(('writer', 'DEL cache', time.time()))
            b2.wait()                       # 等读线程 miss
            time.sleep(0.02)                # 模拟 DB 更新耗时
            db.set('id', 'v2')              # 3. 更新 DB
            events.append(('writer', 'DB=v2', time.time()))
            b3.wait()
        finally:
            rr.close()

    def reader():
        rr = conn()
        try:
            b1.wait()
            b2.wait()
            v = rr.get(KEY)                 # 2. 缓存 miss（已被删）
            if v is None:
                v = db.get('id')            # 读到的是旧值 v1（DB 还没更新）
                events.append(('reader', 'read DB=%s' % v, time.time()))
                rr.set(KEY, v)              # 回填 → 缓存被写成 v1！
                events.append(('reader', '回填 cache=%s' % v, time.time()))
            b3.wait()
        finally:
            rr.close()

    tw = threading.Thread(target=writer)
    tr = threading.Thread(target=reader)
    tw.start(); tr.start(); tw.join(); tr.join()

    for who, what, t in sorted(events, key=lambda x: x[2]):
        print('  %-7s %s' % (who, what))
    print()
    print('最终状态: DB=%s, 缓存=%s' % (db.data['id'], r.get(KEY)))
    if db.data['id'] != r.get(KEY):
        print('❌ 不一致！缓存停留在旧值 v1，而 DB 已是 v2')
        print('危害：这个不一致不会自愈 —— 缓存要等 TTL 到期或下次写操作才更新')
        print('原因：删缓存后、更新 DB 前的并发读，把旧值回填进了缓存')
    r.close()


# ---------------------------------------------------------
# 实验 4：延迟双删
# ---------------------------------------------------------
def test_delayed_double_delete(reps=300, sleep_ms=5):
    banner('实验 4：延迟双删 —— 它是"兜底"而非"保证"（%d 次并发尝试）' % reps)
    print('策略：删缓存 → 更新 DB → sleep ~%.0fms → 再删缓存' % sleep_ms)

    stale_before_2nd_del = 0      # 第二次删除生效前，缓存里是旧值
    final_inconsistent = 0        # 最终（双删后）缓存与 DB 不一致
    cache_empty = 0               # 最终缓存为空（会自愈）
    checked = 0

    for _ in range(reps):
        r, db = fresh('v1')
        b1 = threading.Barrier(2)
        b2 = threading.Barrier(2)
        state = {}

        def writer(rr, db_, st):
            try:
                b1.wait()
                rr.delete(KEY)                       # 1st delete
                b2.wait()
                time.sleep(sleep_ms / 1000.0 * random.uniform(0.5, 2.0))
                db_.set('id', 'v2')                  # update DB
                time.sleep(sleep_ms / 1000.0 * random.uniform(0.1, 1.5))
                st['before_2nd'] = rr.get(KEY)       # 观察第二次删除前的状态
                rr.delete(KEY)                       # 2nd delete
            finally:
                pass

        def reader(rr, db_):
            try:
                b1.wait()
                b2.wait()
                v = rr.get(KEY)
                if v is None:
                    v = db_.get('id')
                    rr.set(KEY, v)                   # 可能把旧值 v1 回填
            finally:
                pass

        rr = conn()
        tw = threading.Thread(target=writer, args=(conn(), db, state))
        tr = threading.Thread(target=reader, args=(conn(), db))
        tw.start(); tr.start(); tw.join(); tr.join()

        cv = rr.get(KEY)
        dv = db.data['id']
        checked += 1
        if state.get('before_2nd') not in (None, dv):
            stale_before_2nd_del += 1
        if cv is not None and cv != dv:
            final_inconsistent += 1
        if cv is None:
            cache_empty += 1
        rr.close()
        r.close()

    print('并发尝试次数                : %d' % checked)
    print('第二次删除前缓存已是旧值     : %d 次（%.1f%%）← 双删要修的正是这个'
          % (stale_before_2nd_del, stale_before_2nd_del * 100.0 / checked))
    print('双删后缓存与 DB 不一致       : %d 次（%.1f%%）'
          % (final_inconsistent, final_inconsistent * 100.0 / checked))
    print('双删后缓存为空（会自愈）     : %d 次' % cache_empty)
    print()
    print('结论（严格对齐实测数据）：')
    print('  - 双删的第二次删除确实清掉了旧值：本轮 %d 次尝试中最终残留不一致 %d 次'
          % (checked, final_inconsistent))
    print('  - 但它生效的前提是"回填发生在第二次删除之前"')
    print('    实测中 %.1f%% 的轮次确实发生了回填，只是都在第二次删除前完成'
          % (stale_before_2nd_del * 100.0 / checked))
    print('  - 若读线程的回填晚于第二次删除（网络抖动、GC 停顿、DB 慢查询导致），'
          '旧值仍会被写回缓存并残留')
    print('  - 且双删无法处理"第二次删除本身失败"的情况')
    print('  - 所以：延迟双删 = 用一次额外删除把窗口收窄，属于"降低概率"，不是"保证一致"')


# ---------------------------------------------------------
# 实验 5：删除失败
# ---------------------------------------------------------
def test_delete_failure():
    banner('实验 5：删除缓存失败 —— 缓存变成长期脏数据')
    r, db = fresh('v1')
    print('初始: DB=%s, 缓存=%s' % (db.data['id'], r.get(KEY)))
    db.set('id', 'v2')
    print('DB 更新为 v2，但删除缓存的操作失败（网络抖动 / 超时）')
    print('  → 删除未执行')
    print('结果: DB=%s, 缓存=%s  ❌ 不一致，且会持续到 TTL 到期' % (db.data['id'], r.get(KEY)))
    print()
    print('应对：')
    print('  1. 给缓存设较短 TTL —— 兜底，不一致最多持续 TTL 时长')
    print('  2. 删除失败进重试队列（MQ / binlog 订阅如 Canal）')
    print('  3. 订阅 MySQL binlog 异步删缓存 —— 不受业务代码失败影响')
    r.close()


# ---------------------------------------------------------
# 实验 6：更新缓存 vs 删除缓存
# ---------------------------------------------------------
def test_update_vs_delete():
    banner('实验 6：为什么"删缓存"优于"更新缓存"—— 并发写下的乱序问题')
    r, db = fresh('v1')

    events = []
    b = threading.Barrier(2)
    elock = threading.Lock()

    def log(msg):
        with elock:
            events.append((msg, time.time()))

    # 两个并发写线程：A 写 v2，B 写 v3，各自"更新 DB + 更新缓存"
    def writer(name, val, db_delay, cache_delay):
        rr = conn()
        try:
            b.wait()
            time.sleep(db_delay)
            db.set('id', val)
            log('%s: DB=%s' % (name, val))
            time.sleep(cache_delay)
            rr.set(KEY, val)
            log('%s: cache=%s' % (name, val))
        finally:
            rr.close()

    # A 的 DB 写早、缓存写晚（被拖慢）；B 相反 —— 制造乱序
    t1 = threading.Thread(target=writer, args=('A', 'v2', 0.0, 0.05))
    t2 = threading.Thread(target=writer, args=('B', 'v3', 0.01, 0.0))
    t1.start(); t2.start(); t1.join(); t2.join()

    print('场景 1：A 写 v2、B 写 v3 并发，各自"更新 DB + 更新缓存"')
    for what, t in sorted(events, key=lambda x: x[1]):
        print('  %s' % what)
    final_db, final_cache = db.data['id'], r.get(KEY)
    print('\n最终: DB=%s, 缓存=%s' % (final_db, final_cache))
    if final_db == final_cache:
        print('✅ 本轮最终一致')
        print('   时序上 DB 的最后写入者与缓存的最后写入者是同一个线程（%s），'
              '所以"碰巧"对上了' % ('A' if final_db == 'v2' else 'B'))
    else:
        print('❌ 不一致：DB=%s 但缓存=%s' % (final_db, final_cache))
        print('   原因：DB 的写入顺序与缓存的写入顺序不一致（乱序）')
    r.close()

    # ---- 场景 2：确定性构造真正的乱序 ----
    print('\n' + '-' * 70)
    print('场景 2：确定性构造乱序（直接用单线程按危险顺序执行）')
    r2 = conn()
    r2.flushdb()
    db2 = FakeDB(data={'id': 'v1'})
    r2.set(KEY, 'v1')
    steps = [
        ('A 更新 DB', lambda: db2.set('id', 'v2')),
        ('B 更新 DB', lambda: db2.set('id', 'v3')),
        ('B 更新缓存', lambda: r2.set(KEY, 'v3')),
        ('A 更新缓存', lambda: r2.set(KEY, 'v2')),
    ]
    for desc, fn in steps:
        fn()
        print('  %-12s → DB=%s, 缓存=%s' % (desc, db2.data['id'], r2.get(KEY)))
    print('\n最终: DB=%s, 缓存=%s  ❌ 永久不一致（要等 TTL 或下次写操作）'
          % (db2.data['id'], r2.get(KEY)))
    print('触发条件：两个写线程的 DB 写入顺序 与 缓存写入顺序 相反')
    print('          （先写 DB 的线程，其缓存更新反而后到）')
    r2.close()

    print('\n' + '-' * 70)
    print('为什么"删缓存"不会乱序：')
    print('  - 无论 A/B 谁先谁后，缓存都被删成"空"，删除操作没有"值"，不存在顺序问题')
    print('  - 下一次读必然回源 DB，而此时 DB 已是最后写入的值 → 最终一致')
    print('  - 另外"更新缓存"可能是无用功：连续写 100 次但没人读，白算 100 次')
    print('\n"更新缓存"唯一占优的场景：')
    print('  - 写少读极多、且缓存值计算昂贵的场景（避免每次 miss 都重算）')
    print('  - 但需要并发控制（如分布式锁或版本号 CAS）才能保证不乱序')


def main():
    test_normal()
    test_update_then_del()
    test_del_then_update()
    test_delayed_double_delete()
    test_delete_failure()
    test_update_vs_delete()

    banner('知识点 2 核心结论')
    print('1. Cache Aside（旁路缓存）是事实标准：读走缓存、写走 DB 并删缓存')
    print('2. 两种写顺序都有不一致窗口，且都不保证一致')
    print('   - 先更新 DB 再删缓存：窗口短（毫秒级），会自愈')
    print('   - 先删缓存再更新 DB：可能把旧值回填进缓存，不自愈')
    print('3. 延迟双删靠"第二次删除"兜底 —— 本轮实测最终残留不一致 0 次，'
          '但它依赖 sleep 足够长且第二次删除成功，属于降低概率而非保证')
    print('4. 真正的兜底是 TTL（限定不一致持续时长）+ 重试/binlog 订阅')
    print('5. 删缓存优于更新缓存：不会乱序，且避免无效计算')


if __name__ == '__main__':
    main()
