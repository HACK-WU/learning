#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 · 应用实战：跨服务下单，三跳演进

主线场景（承课 9）：下单服务要干两件事——
  ① 在自己库里记一笔订单
  ② 通知库存服务"减 1 件"

第 1 步  写完库直接发消息（双写）        → 丢事件、幽灵事件
第 2 步  + 事务性发件箱                   → 不丢了，但开始重复
第 3 步  + 消费端幂等去重                 → 重复被吸收，终态正确

同一份故障脚本贯穿三跳（同 seed、同故障点），只有实现方式在变，
这样每一步的差值就只来自"这一跳加了什么"。

零第三方依赖。python3 app10_outbox_journey.py
"""

import atexit
import os
import random
import sqlite3
import tempfile
import threading
import time
from collections import Counter

TMP = tempfile.mkdtemp(prefix="app10_")

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

ORDER_DB = os.path.join(TMP, "order.db")
STOCK_DB = os.path.join(TMP, "stock.db")

N = 200                     # 下单笔数
INIT_STOCK = 1000

# 故障注入比例（三跳共用同一份，保证可对照）
P_CRASH_AFTER_COMMIT = 0.05     # 库提交后、发消息前崩掉
P_BROKER_DOWN = 0.08            # 消息通道临时不可用
P_RELAY_CRASH = 0.10            # 中继发完、未标记时崩
P_CONSUMER_CRASH = 0.10         # 消费端处理完、未 ack 时崩
P_DUP_DELIVERY = 0.15           # 通道重复投递

EVENTS = []                     # 消息通道里的消息（含重复）
STOCK_APPLIED = []              # 库存服务实际执行的扣减（每次执行一条）


def conn(path):
    c = sqlite3.connect(path, timeout=10.0, isolation_level=None)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA busy_timeout=10000")
    return c


def setup():
    for p in (ORDER_DB, STOCK_DB):
        if os.path.exists(p):
            os.remove(p)
    c = conn(ORDER_DB)
    c.execute("""CREATE TABLE orders(
        id INTEGER PRIMARY KEY, sku TEXT, qty INTEGER,
        status TEXT NOT NULL DEFAULT 'created')""")
    c.execute("""CREATE TABLE outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        aggregateid TEXT NOT NULL,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at REAL NOT NULL,
        published_at REAL)""")
    c.close()

    s = conn(STOCK_DB)
    s.execute("CREATE TABLE stock(sku TEXT PRIMARY KEY, qty INTEGER)")
    s.execute("CREATE TABLE inbox(msg_id TEXT PRIMARY KEY, processed_at REAL NOT NULL)")
    s.execute("INSERT INTO stock VALUES('A-1', ?)", (INIT_STOCK,))
    s.close()


def stock_qty():
    s = conn(STOCK_DB)
    q = s.execute("SELECT qty FROM stock WHERE sku='A-1'").fetchone()[0]
    s.close()
    return q


def order_count():
    c = conn(ORDER_DB)
    n = c.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    c.close()
    return n


def pending_outbox():
    c = conn(ORDER_DB)
    n = c.execute("SELECT COUNT(*) FROM outbox WHERE published_at IS NULL").fetchone()[0]
    c.close()
    return n


# ---------------------------------------------------------------- 第 1 步：双写
def step1(N, faults):
    """写完库直接发消息。"""
    for i in range(N):
        oid = 1000 + i
        c = conn(ORDER_DB)
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders(id,sku,qty) VALUES(?,?,?)", (oid, "A-1", 1))
        c.execute("COMMIT")
        c.close()

        if faults["crash"][i]:
            continue                                   # 进程没了，消息永远不发

        if faults["broker"][i]:
            continue                                   # 通道不可用，消息丢了

        EVENTS.append(f"OrderCreated:{oid}")

        if faults["dup"][i]:
            EVENTS.append(f"OrderCreated:{oid}")       # 通道重复投递

    # 消费端：收到就扣（无幂等）
    for e in EVENTS:
        oid = e.split(":")[1]
        s = conn(STOCK_DB)
        s.execute("BEGIN IMMEDIATE")
        s.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
        s.execute("COMMIT")
        s.close()
        STOCK_APPLIED.append(oid)


# ---------------------------------------------------------------- 第 2 步：+ 发件箱
def step2(N, faults):
    """业务写 + outbox 写同事务；中继负责发。消费端仍无幂等。"""
    for i in range(N):
        oid = 1000 + i
        c = conn(ORDER_DB)
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders(id,sku,qty) VALUES(?,?,?)", (oid, "A-1", 1))
        c.execute("""INSERT INTO outbox(aggregateid,type,payload,created_at)
                     VALUES(?,?,?,?)""",
                  (str(oid), "OrderCreated", f'{{"orderId":{oid}}}', time.time()))
        c.execute("COMMIT")
        c.close()

    # 中继：扫未发布 → 发 → 标记。名"发完未标记就崩"的窗口
    crashed = False
    c = conn(ORDER_DB)
    rows = c.execute("""SELECT id, aggregateid FROM outbox
                        WHERE published_at IS NULL ORDER BY id""").fetchall()
    c.close()
    for idx, (rid, aid) in enumerate(rows):
        if faults["relay"][idx] and not crashed:
            # 已经发出去了，但没标记 → 重启后会重发
            EVENTS.append(f"OrderCreated:{aid}")
            crashed = True
            continue
        if faults["broker"][idx]:
            continue                                  # 通道不可用，这轮发不出去
        EVENTS.append(f"OrderCreated:{aid}")
        if faults["dup"][idx]:
            EVENTS.append(f"OrderCreated:{aid}")

    # 被崩溃打断的那一轮没标记，重跑一次把剩下的发完
    c = conn(ORDER_DB)
    c.execute("BEGIN IMMEDIATE")
    rows = c.execute("""SELECT id, aggregateid FROM outbox
                        WHERE published_at IS NULL ORDER BY id""").fetchall()
    for rid, aid in rows:
        if not any(e.endswith(":" + aid) for e in EVENTS):
            EVENTS.append(f"OrderCreated:{aid}")
        c.execute("UPDATE outbox SET published_at=? WHERE id=?", (time.time(), rid))
    c.execute("COMMIT")
    c.close()

    # 消费端：仍然无幂等
    for e in EVENTS:
        oid = e.split(":")[1]
        s = conn(STOCK_DB)
        s.execute("BEGIN IMMEDIATE")
        s.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
        s.execute("COMMIT")
        s.close()
        STOCK_APPLIED.append(oid)


# ---------------------------------------------------------------- 第 3 步：+ 幂等
def step3(N, faults):
    """发件箱 + 消费端去重表（同事务）。"""
    for i in range(N):
        oid = 1000 + i
        c = conn(ORDER_DB)
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders(id,sku,qty) VALUES(?,?,?)", (oid, "A-1", 1))
        c.execute("""INSERT INTO outbox(aggregateid,type,payload,created_at)
                     VALUES(?,?,?,?)""",
                  (str(oid), "OrderCreated", f'{{"orderId":{oid}}}', time.time()))
        c.execute("COMMIT")
        c.close()

    # 中继 + 消费端联合处理：先发，消费端落去重表；再标记
    c = conn(ORDER_DB)
    rows = c.execute("""SELECT id, aggregateid FROM outbox
                        WHERE published_at IS NULL ORDER BY id""").fetchall()
    c.close()

    for idx, (rid, aid) in enumerate(rows):
        msg_id = f"order-created-{aid}"        # 发送方生成的消息身份，重发不变

        # 消费端处理（去重表 + 业务同一个事务）
        s = conn(STOCK_DB)
        ok = False
        try:
            s.execute("BEGIN IMMEDIATE")
            s.execute("INSERT INTO inbox VALUES(?,?)", (msg_id, time.time()))
            s.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
            if faults["consumer"][idx]:
                s.execute("ROLLBACK")           # 崩在提交前：两件事都没做，消息会被重投
            else:
                s.execute("COMMIT")
                STOCK_APPLIED.append(aid)
                ok = True
        except sqlite3.IntegrityError:
            s.execute("ROLLBACK")               # 重复消息：整体跳过
            ok = True                           # 已处理过，可以安全标记
        finally:
            s.close()

        # 只有消费端确认过（成功或判定重复）才标记；崩溃的不标记 → 留待重投
        if ok and not faults["relay"][idx]:
            c = conn(ORDER_DB)
            c.execute("BEGIN IMMEDIATE")
            c.execute("UPDATE outbox SET published_at=? WHERE id=?", (time.time(), rid))
            c.execute("COMMIT")
            c.close()

    # 重投：所有没被标记的都再走一遍（消息 id 不变，去重表生效）
    c = conn(ORDER_DB)
    c.execute("BEGIN IMMEDIATE")
    rows = c.execute("""SELECT id, aggregateid FROM outbox
                        WHERE published_at IS NULL ORDER BY id""").fetchall()
    for rid, aid in rows:
        msg_id = f"order-created-{aid}"
        s = conn(STOCK_DB)
        try:
            s.execute("BEGIN IMMEDIATE")
            s.execute("INSERT INTO inbox VALUES(?,?)", (msg_id, time.time()))
            s.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
            s.execute("COMMIT")
            STOCK_APPLIED.append(aid)
        except sqlite3.IntegrityError:
            s.execute("ROLLBACK")               # 已经处理过，跳过
        finally:
            s.close()
        c.execute("UPDATE outbox SET published_at=? WHERE id=?", (time.time(), rid))
    c.execute("COMMIT")
    c.close()


# ---------------------------------------------------------------- 故障脚本
def make_faults(N, seed=7):
    rnd = random.Random(seed)
    return {
        "crash": [rnd.random() < P_CRASH_AFTER_COMMIT for _ in range(N)],
        "broker": [rnd.random() < P_BROKER_DOWN for _ in range(N)],
        "relay": [rnd.random() < P_RELAY_CRASH for _ in range(N)],
        "consumer": [rnd.random() < P_CONSUMER_CRASH for _ in range(N)],
        "dup": [rnd.random() < P_DUP_DELIVERY for _ in range(N)],
    }


def run_step(label, fn):
    global EVENTS, STOCK_APPLIED
    EVENTS = []
    STOCK_APPLIED = []
    setup()
    faults = make_faults(N)
    fn(N, faults)

    n_orders = order_count()
    q = stock_qty()
    deducted = INIT_STOCK - q
    expected = n_orders                    # 每笔订单应扣 1 件
    applied = len(STOCK_APPLIED)
    uniq_applied = len(set(STOCK_APPLIED))
    return {
        "label": label,
        "orders": n_orders,
        "deducted": deducted,
        "expected": expected,
        "applied": applied,
        "uniq_applied": uniq_applied,
        "pending": pending_outbox(),
        "ok": deducted == expected,
    }


def main():
    print("=" * 80)
    print("课 10 · 应用实战  跨服务下单：双写 → 发件箱 → 幂等消费")
    print(f"订单库 {ORDER_DB}")
    print(f"库存库 {STOCK_DB}")
    print(f"下单 {N} 笔｜初始库存 {INIT_STOCK}｜同一份故障脚本贯穿三跳（seed=7）")
    print("=" * 80)
    print()
    print("故障注入比例：提交后崩溃 5%｜通道不可用 8%｜中继发完未标记 10%")
    print("              消费端提交前崩溃 10%｜通道重复投递 15%")
    print()

    results = [
        run_step("第 1 步 双写", step1),
        run_step("第 2 步 + 发件箱", step2),
        run_step("第 3 步 + 幂等消费", step3),
    ]

    print(f"{'做法':<20}{'订单':>6}{'库存扣减':>10}{'应扣':>6}{'偏差':>8}{'待发':>6}{'终态':>10}")
    print("-" * 80)
    for r in results:
        diff = r["deducted"] - r["expected"]
        verdict = "✓ 一致" if r["ok"] else f"✗ 偏 {diff:+d}"
        print(f"{r['label']:<20}{r['orders']:>6}{r['deducted']:>10}"
              f"{r['expected']:>6}{diff:>+8}{r['pending']:>6}{verdict:>10}")

    print()
    print("【逐跳解释】")
    r1, r2, r3 = results

    print(f"  第 1 步：订单 {r1['orders']} 笔，库存扣了 {r1['deducted']} 件（应扣 {r1['expected']}）。")
    print(f"    净偏差 {r1['deducted'] - r1['expected']:+d} —— 这个数字很危险：它看起来「差不多对」，")
    print(f"    实际是两股相反的错互相抵消：一批订单丢了事件（少扣），")
    print(f"    另一批订单被重复投递（多扣）。净值接近 0，但账面已经错了。")
    print(f"    → 只看总量核对，第 1 步会伪装成「基本没问题」。")
    print()
    print(f"  第 2 步：订单 {r2['orders']} 笔，库存扣了 {r2['deducted']} 件（应扣 {r2['expected']}）。")
    print(f"    丢事件被治好了（待发 {r2['pending']} 条 = 都能补发），")
    print(f"    但扣多了 {r2['deducted'] - r2['expected']:+d} 件 —— 重复投递 + 中继重发叠在一起。")
    print(f"    库存服务执行了 {r2['applied']} 次扣减，其中只有 {r2['uniq_applied']} 次是不同订单。")
    print()
    print(f"  第 3 步：订单 {r3['orders']} 笔，库存扣了 {r3['deducted']} 件，偏差 {r3['deducted'] - r3['expected']:+d}。")
    print(f"    消费端落去重表后，重复消息在第二次进来时撞主键、整体回滚。")
    print(f"    执行了 {r3['applied']} 次扣减 = 唯一订单 {r3['uniq_applied']} 笔，一次不多一次不少。")
    print()
    print("=" * 80)
    print("一句话：第 2 步把「丢」换成「重」，第 3 步把「重」收成「一次」。")
    print("        三步缺一不可：少了第 2 步会丢，少了第 3 步会多。")
    print("=" * 80)


if __name__ == "__main__":
    main()
