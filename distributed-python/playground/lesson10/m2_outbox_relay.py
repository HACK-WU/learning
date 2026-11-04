#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 · 机制实验 2：事务性发件箱

把「发消息」从请求路径上摘掉，改成往同一个库里的 outbox 表插一行。
业务写和 outbox 写共享一个本地事务 —— 于是"事件是否存在"变成"业务是否提交"的
同一个布尔值，不再有中间窗口。

五个回合：
  R1 崩溃窗口对比    双写 vs 发件箱：同样的崩溃注入，一个丢事件，一个不丢
  R2 中继重发        中继在"发出去了但还没标记"的瞬间崩掉 → 同一条会被发两次
  R3 高水位跳行      用"记住最大 id 往上扫"的中继，会漏掉晚提交的小 id 行
  R4 中继并发        两个中继同时扫同一批 → 重复投递翻倍
  R5 表只涨不消      不发清理任务，outbox 行数随时间线性增长

零第三方依赖。python3 m2_outbox_relay.py
"""

import atexit
import os
import random
import sqlite3
import tempfile
import threading
import time

TMP = tempfile.mkdtemp(prefix="m2ob_")

def _cleanup_tmp():
    """退出时删掉本次运行在 /tmp 下建的目录。

    保留现场：设置环境变量 KEEP_TMP=1 或传 --keep，目录会保留并打印路径。
    """
    import shutil, sys
    if os.environ.get("KEEP_TMP") == "1" or "--keep" in sys.argv:
        print(f"\n（已保留临时目录：{TMP}）")
        return
    shutil.rmtree(TMP, ignore_errors=True)


atexit.register(_cleanup_tmp)

DB = os.path.join(TMP, "svc.db")

PUBLISHED = []          # 中继成功投递出去的消息（可能重复）
STATS = {}


def conn(isolation_level=None):
    c = sqlite3.connect(DB, timeout=10.0, isolation_level=isolation_level)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA busy_timeout=10000")
    return c


def setup():
    c = conn()
    c.execute("DROP TABLE IF EXISTS orders")
    c.execute("DROP TABLE IF EXISTS outbox")
    c.execute("""CREATE TABLE orders(
        id INTEGER PRIMARY KEY, sku TEXT, qty INTEGER CHECK(qty > 0))""")
    # 发件箱表：列名对齐 Debezium 默认，便于将来换 CDC 中继
    c.execute("""CREATE TABLE outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        aggregatetype TEXT NOT NULL,
        aggregateid TEXT NOT NULL,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at REAL NOT NULL,
        published_at REAL)""")
    c.execute("""CREATE INDEX outbox_unpublished
                 ON outbox(id) WHERE published_at IS NULL""")
    c.close()


def reset_data():
    c = conn()
    c.execute("DELETE FROM orders")
    c.execute("DELETE FROM outbox")
    c.execute("DELETE FROM sqlite_sequence WHERE name='outbox'")
    c.close()
    PUBLISHED.clear()
    STATS.clear()


# ---------------------------------------------------------------- 写侧
def place_order_dual_write(oid, qty=1, crash_before_publish=False):
    """反例：先写库、再发消息（两个系统，没有共享事务）。"""
    c = conn()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders VALUES(?,?,?)", (oid, "A-1", qty))
        c.execute("COMMIT")
    except sqlite3.IntegrityError:
        c.execute("ROLLBACK")
        c.close()
        return "db-fail"
    c.close()
    if crash_before_publish:
        return "crash-before-publish"     # 进程在这儿没了
    PUBLISHED.append(f"order-created:{oid}")
    return "ok"


def place_order_outbox(oid, qty=1, crash_before_relay=False):
    """正解：业务写 + 发件箱写，同一个本地事务。"""
    c = conn()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders VALUES(?,?,?)", (oid, "A-1", qty))
        c.execute(
            "INSERT INTO outbox(aggregatetype,aggregateid,type,payload,created_at)"
            " VALUES(?,?,?,?,?)",
            ("order", str(oid), "OrderCreated",
             f'{{"orderId":{oid},"sku":"A-1","qty":{qty}}}', time.time()),
        )
        c.execute("COMMIT")
        return "committed"                # 两行同生共死
    except sqlite3.IntegrityError:
        c.execute("ROLLBACK")
        return "rolled-back"
    finally:
        c.close()


# ---------------------------------------------------------------- 中继
def relay_polling(limit=100, crash_after_publish=False, mark=True):
    """轮询中继：读未发布行 → 发 → 标记。

    三个动作不是原子的：发成功与标记成功之间有一个窗口。
    在这个窗口崩溃，重启后同一条会被再发一次。
    """
    c = conn()
    rows = c.execute(
        "SELECT id, aggregatetype, aggregateid, type, payload"
        " FROM outbox WHERE published_at IS NULL ORDER BY id LIMIT ?", (limit,)
    ).fetchall()
    if not rows:
        c.close()
        return 0

    sent_ids = []
    for rid, atype, aid, etype, payload in rows:
        PUBLISHED.append(f"{etype.lower()}:{aid}")
        sent_ids.append(rid)
        if crash_after_publish and len(sent_ids) == 1:
            c.close()
            raise RuntimeError("relay crashed after publish, before mark")

    if mark:
        c.execute("BEGIN IMMEDIATE")
        c.executemany("UPDATE outbox SET published_at=? WHERE id=?",
                      [(time.time(), i) for i in sent_ids])
        c.execute("COMMIT")
    c.close()
    return len(sent_ids)


def relay_high_water(limit=100):
    """反例中继：记住见过的最大 id，只扫 id 更大的。

    看起来高效，实际会漏行：id 在插入时分配，不是提交时分配。
    一个慢事务拿到小 id、晚提交，等它落库时高水位早就越过它了。
    """
    c = conn()
    hw = c.execute(
        "SELECT COALESCE(MAX(id),0) FROM outbox WHERE published_at IS NOT NULL"
    ).fetchone()[0]
    rows = c.execute(
        "SELECT id, type, aggregateid FROM outbox"
        " WHERE id > ? AND published_at IS NULL ORDER BY id LIMIT ?", (hw, limit)
    ).fetchall()
    for rid, etype, aid in rows:
        PUBLISHED.append(f"{etype.lower()}:{aid}")
    if rows:
        c.execute("BEGIN IMMEDIATE")
        c.executemany("UPDATE outbox SET published_at=? WHERE id=?",
                      [(time.time(), r[0]) for r in rows])
        c.execute("COMMIT")
    c.close()
    return len(rows)


# ---------------------------------------------------------------- 回合
def r1_crash_window():
    print("【R1 同样的崩溃注入，两条路的结果】")
    print(f"{'做法':<22}{'订单行':>8}{'outbox待发':>12}{'下游收到':>10}{'一致?':>8}")
    print("-" * 74)

    reset_data()
    place_order_dual_write(1, crash_before_publish=True)
    n = conn().execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    print(f"{'双写 + 发送前崩溃':<22}{n:>8}{'—':>12}{len(PUBLISHED):>10}{'✗ 丢事件':>8}")

    reset_data()
    place_order_outbox(2, crash_before_relay=True)
    c = conn()
    n = c.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    pend = c.execute("SELECT COUNT(*) FROM outbox WHERE published_at IS NULL").fetchone()[0]
    c.close()
    # 进程崩了，但重启后中继照样能捡起来
    relay_polling()
    print(f"{'发件箱 + 发送前崩溃':<22}{n:>8}{pend:>12}{len(PUBLISHED):>10}{'✓':>8}")

    print()
    print("  差别不在「谁更快」，在于：崩溃之后，那条还没发的事件还在不在库里。")
    print("  发件箱把它变成了数据 —— 进程死了，数据还活着，重启就能接着发。")
    print()

    # 事务原子性
    reset_data()
    r = place_order_outbox(3, qty=0)     # 业务写失败
    c = conn()
    n = c.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    ob = c.execute("SELECT COUNT(*) FROM outbox").fetchone()[0]
    c.close()
    print(f"  R1b 业务写失败（qty=0）时：订单 {n} 行、outbox {ob} 行（返回 {r}）")
    print("      → 两行一起回滚。事件存在当且仅当业务提交，这是同一个布尔值。")
    print()


def r2_relay_duplicate():
    print("【R2 中继在「发完、还没标记」时崩溃 → 同一条会发两次】")
    reset_data()
    place_order_outbox(10)
    place_order_outbox(11)
    try:
        relay_polling(crash_after_publish=True)
    except RuntimeError as e:
        print(f"  中继异常：{e}")
    before = len(PUBLISHED)
    relay_polling()      # 重启后重扫：那条没标记的又发了一次
    after = len(PUBLISHED)
    print(f"  崩溃前已发出 {before} 条；重启后累计 {after} 条")
    from collections import Counter
    dup = {k: v for k, v in Counter(PUBLISHED).items() if v > 1}
    print(f"  重复投递：{dup if dup else '无'}")
    print(f"  → 投递语义 = at-least-once（至少一次），不是 exactly-once。")
    print(f"  → 这个重复是设计内的，不是 bug：中继无法把「发」和「标记」变成原子操作。")
    print()


def r3_high_water_skip():
    print("【R3 高水位中继会永久漏行：id 顺序 ≠ 提交顺序】")
    print("    注：sqlite 同一时刻只允许一个写者，无法复现「两个写事务并发、一个晚提交」。")
    print("    这里用「乱序可见」等价演示同一算法缺陷（PostgreSQL/MySQL 下是真并发）。")
    print()
    reset_data()

    # 造出两行待发：真实数据库里它们由两个并发事务产生，
    # 其中 id 小的那个晚提交，因此中继先看到的是 id 大的。
    c = conn()
    c.execute("BEGIN IMMEDIATE")
    c.execute("INSERT INTO orders VALUES(100,'A-1',1)")
    c.execute("INSERT INTO outbox(aggregatetype,aggregateid,type,payload,created_at)"
              " VALUES('order','100','OrderCreated','{}',?)", (time.time(),))
    slow_id = c.execute("SELECT MAX(id) FROM outbox").fetchone()[0]
    c.execute("INSERT INTO orders VALUES(101,'A-1',1)")
    c.execute("INSERT INTO outbox(aggregatetype,aggregateid,type,payload,created_at)"
              " VALUES('order','101','OrderCreated','{}',?)", (time.time(),))
    fast_id = c.execute("SELECT MAX(id) FROM outbox").fetchone()[0]
    c.execute("COMMIT")
    c.close()

    # 中继先只处理 id 大的那一条（模拟快事务先提交、先被扫到）
    c = conn()
    c.execute("BEGIN IMMEDIATE")
    c.execute("UPDATE outbox SET published_at=? WHERE id=? AND aggregateid='101'",
              (time.time(), fast_id))
    c.execute("COMMIT")
    hw = c.execute(
        "SELECT COALESCE(MAX(id),0) FROM outbox WHERE published_at IS NOT NULL"
    ).fetchone()[0]
    c.close()
    PUBLISHED.append(f"ordercreated:101")

    # 之后无论再跑多少轮，高水位都已经越过 slow_id
    rounds = []
    for _ in range(3):
        rounds.append(relay_high_water())

    c = conn()
    stuck = c.execute(
        "SELECT id, aggregateid FROM outbox WHERE published_at IS NULL").fetchall()
    c.close()

    print(f"  两行待发：id={slow_id}（aggregateid=100）、id={fast_id}（aggregateid=101）")
    print(f"  中继先处理了 id={fast_id}，此时高水位 hw={hw}")
    print(f"  之后连跑 3 轮，每轮发出：{rounds} 条")
    print(f"  仍未发布的 outbox 行：{stuck}")
    print()
    print(f"  → id={slow_id} 被永久跳过：高水位已经越过它，之后所有扫描都从 hw+1 开始。")
    print(f"  → 正解：按「是否已发布」扫描（published_at IS NULL），不要按 id 高水位。")
    print(f"     WHERE 条件配合 (published_at) 局部索引，扫的是「没发的那几条」，")
    print(f"     而不是「id 比某个数大的」，因此晚到的行不会漏。")
    print()


def r4_relay_concurrency():
    print("【R4 两个中继实例同时扫同一批 → 重复投递翻倍】")
    reset_data()
    for i in range(20):
        place_order_outbox(200 + i)
    PUBLISHED.clear()

    results = []

    def worker():
        try:
            n = relay_polling(limit=100, mark=True)
            results.append(n)
        except sqlite3.OperationalError as e:
            results.append(f"err:{e}")

    ts = [threading.Thread(target=worker) for _ in range(2)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()

    from collections import Counter
    dup = sum(v - 1 for v in Counter(PUBLISHED).values() if v > 1)
    print(f"  待发 20 条，两个中继各扫一轮")
    print(f"  实际投递 {len(PUBLISHED)} 次，重复投递 {dup} 次")
    print(f"  → 没有租约/声明机制时，n 个中继就是 n 倍重复量。")
    print(f"  → 真实做法：FOR UPDATE SKIP LOCKED，或先领取再发（lease）。")
    print()


def r5_table_growth():
    print("【R5 不发清理任务，outbox 表只涨不消】")
    reset_data()
    marks = []
    for batch in range(5):
        for i in range(100):
            place_order_outbox(1000 + batch * 100 + i)
        relay_polling(limit=1000)
        c = conn()
        total = c.execute("SELECT COUNT(*) FROM outbox").fetchone()[0]
        done = c.execute("SELECT COUNT(*) FROM outbox WHERE published_at IS NOT NULL").fetchone()[0]
        c.close()
        marks.append((batch + 1, total, done))

    print(f"  {'批次':<8}{'outbox总行数':>14}{'其中已发布':>12}{'增量':>10}")
    for b, t, d in marks:
        print(f"  第{b}批{'':<6}{t:>14}{d:>12}{100:>10}")
    print()
    print("  → 已发布的行如果从不删除，表会一直涨；而中继的查询是")
    print("     WHERE published_at IS NULL —— 索引虽小，表体积和 VACUUM 压力照样在涨。")
    print("  → 真实做法：定期删除/归档已发布行（保留一段时间供排查）。")
    print()


def main():
    print("=" * 74)
    print("课 10 · M2  事务性发件箱与中继")
    print(f"库文件：{DB}")
    print("=" * 74)
    print()
    setup()
    r1_crash_window()
    r2_relay_duplicate()
    r3_high_water_skip()
    r4_relay_concurrency()
    r5_table_growth()
    print("=" * 74)
    print("一句话：发件箱没有让「两件事」变成「一件事」，")
    print("        它只是把第二件事从「网络」换成了「同一张表里的一行」。")
    print("=" * 74)


if __name__ == "__main__":
    main()
