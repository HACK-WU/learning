#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 · 机制实验 3：幂等消费与去重表

发件箱保证了「至少一次」，于是消费端必然收到重复。
本实验用同一个下游动作（扣库存），对比四种消费写法在同一串消息下的最终结果：

  S1 裸消费            收到就扣，重复就多扣
  S2 业务判断幂等      先查再改，两条消息交错时仍然坏
  S3 去重表 + 业务分离  先插去重表、再改业务，但两者不在同一事务 → 中间崩溃会丢
  S4 去重表 + 同事务    插去重表与改业务在同一个本地事务 → 正确

再补两个容易被忽略的回合：
  R5 去重键选错        用「第几次投递」当键 → 去重表形同虚设
  R6 去重表也涨        不清理 → 与 outbox 同样的表体积问题

零第三方依赖。python3 m3_idempotent_consumer.py
"""

import atexit
import os
import sqlite3
import tempfile
import time

TMP = tempfile.mkdtemp(prefix="m3id_")

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

DB = os.path.join(TMP, "consumer.db")

INIT_STOCK = 1000


def conn():
    c = sqlite3.connect(DB, timeout=10.0, isolation_level=None)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA busy_timeout=10000")
    return c


def setup():
    c = conn()
    for t in ("stock", "inbox", "inbox_bad", "inbox_naive"):
        c.execute(f"DROP TABLE IF EXISTS {t}")
    c.execute("CREATE TABLE stock(sku TEXT PRIMARY KEY, qty INTEGER)")
    c.execute("""CREATE TABLE inbox(
        msg_id TEXT PRIMARY KEY,
        processed_at REAL NOT NULL)""")
    # S2 用的朴素「处理日志」表：只有自增主键，没有唯一约束 —— 现实中大量存在
    c.execute("""CREATE TABLE inbox_naive(
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        msg_id TEXT NOT NULL,
        processed_at REAL NOT NULL)""")
    # 反例：用「第几次投递」当去重键 —— 永远是新的，永远去不掉
    c.execute("""CREATE TABLE inbox_bad(
        delivery_no INTEGER PRIMARY KEY,
        msg_id TEXT NOT NULL,
        processed_at REAL NOT NULL)""")
    c.close()
    reset_stock()


def reset_stock():
    c = conn()
    c.execute("INSERT OR REPLACE INTO stock VALUES('A-1', ?)", (INIT_STOCK,))
    c.execute("DELETE FROM inbox")
    c.execute("DELETE FROM inbox_naive")
    c.execute("DELETE FROM inbox_bad")
    c.close()


def stock():
    c = conn()
    v = c.execute("SELECT qty FROM stock WHERE sku='A-1'").fetchone()[0]
    c.close()
    return v


# ---------------------------------------------------------------- 四种消费写法
def consume_raw(msg_id, qty=1):
    """S1：收到就扣。重复消息 = 重复扣。"""
    c = conn()
    c.execute("BEGIN IMMEDIATE")
    c.execute("UPDATE stock SET qty=qty-? WHERE sku='A-1'", (qty,))
    c.execute("COMMIT")
    c.close()
    return "deducted"


def consume_check_then_act(msg_id, qty=1):
    """S2：先查处理日志，再改业务 —— 最常见也最容易写错的写法。

    两个致命点：
      ① 那次 SELECT 在事务之外（或虽在事务内，但表上没有唯一约束）
      ② 「改业务」和「记日志」之间没有任何互斥
    真实并发下两个消费者可以同时查到"没处理过"，然后各扣一次。
    """
    c = conn()
    seen = c.execute("SELECT 1 FROM inbox_naive WHERE msg_id=?", (msg_id,)).fetchone()
    c.close()
    if seen:
        return "skipped"

    # 查完之后：改业务
    c = conn()
    c.execute("BEGIN IMMEDIATE")
    c.execute("UPDATE stock SET qty=qty-? WHERE sku='A-1'", (qty,))
    c.execute("COMMIT")
    c.close()

    # 再补一条处理日志（此时才能被发现"处理过"）
    c = conn()
    c.execute("INSERT INTO inbox_naive(msg_id, processed_at) VALUES(?,?)",
              (msg_id, time.time()))
    c.close()
    return "deducted"


def consume_split_tx(msg_id, qty=1, crash_after_mark=False):
    """S3：先插去重表并提交，再改业务（两个事务）。

    中间崩溃 → 去重表说"处理过了"，业务其实没做 → 永久丢一次扣减。
    """
    c = conn()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO inbox VALUES(?,?)", (msg_id, time.time()))
        c.execute("COMMIT")
    except sqlite3.IntegrityError:
        c.execute("ROLLBACK")
        c.close()
        return "duplicate-skipped"
    c.close()

    if crash_after_mark:
        return "crash-after-mark"      # 进程死在这儿

    c = conn()
    c.execute("BEGIN IMMEDIATE")
    c.execute("UPDATE stock SET qty=qty-? WHERE sku='A-1'", (qty,))
    c.execute("COMMIT")
    c.close()
    return "deducted"


def consume_same_tx(msg_id, qty=1, crash_before_commit=False):
    """S4：插去重表与改业务在同一个本地事务。

    重复消息撞主键 → 整个事务回滚 → 业务也没做。
    崩溃发生在 commit 之前 → 两件事一起没发生，消息重投时还能正常处理。
    """
    c = conn()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO inbox VALUES(?,?)", (msg_id, time.time()))
        c.execute("UPDATE stock SET qty=qty-? WHERE sku='A-1'", (qty,))
        if crash_before_commit:
            c.execute("ROLLBACK")
            c.close()
            return "crash-before-commit"
        c.execute("COMMIT")
        c.close()
        return "deducted"
    except sqlite3.IntegrityError:
        c.execute("ROLLBACK")
        c.close()
        return "duplicate-skipped"


# ---------------------------------------------------------------- 回合
def run_batch(handler, deliveries, label, extra=None):
    reset_stock()
    seen = {}
    for msg_id in deliveries:
        if extra:
            r = handler(msg_id, **extra)
        else:
            r = handler(msg_id)
        seen[r] = seen.get(r, 0) + 1
    q = stock()
    deducted = INIT_STOCK - q
    unique = len(set(deliveries))
    return {
        "label": label,
        "deliveries": len(deliveries),
        "unique": unique,
        "deducted": deducted,
        "expected": unique,
        "ok": deducted == unique,
        "seen": seen,
    }


def r1_four_ways():
    print("【R1 同一串消息（10 条唯一，重复投递到 18 次）喂给四种写法】")
    print()

    # 构造投递序列：m1..m10，其中 8 条各被投递了 2 次
    deliveries = []
    for i in range(1, 11):
        deliveries.append(f"m{i}")
        if i <= 8:
            deliveries.append(f"m{i}")     # 重复投递
    # 打散一下，模拟乱序到达
    deliveries = deliveries[::2] + deliveries[1::2]

    print(f"  投递总数 {len(deliveries)} 次，唯一消息 {len(set(deliveries))} 条")
    print(f"  正确答案：库存应从 {INIT_STOCK} 扣到 {INIT_STOCK - 10}")
    print()
    print(f"  {'写法':<30}{'扣减量':>8}{'应为':>6}{'结果':>16}")
    print("  " + "-" * 68)

    cases = [
        (consume_raw, "S1 裸消费"),
        (consume_check_then_act, "S2 先查再改"),
        (consume_split_tx, "S3 去重表与业务分两个事务"),
        (consume_same_tx, "S4 去重表与业务同事务"),
    ]
    rows = []
    for fn, label in cases:
        r = run_batch(fn, deliveries, label)
        rows.append(r)
        verdict = "✓ 正确" if r["ok"] else f"✗ 多扣 {r['deducted'] - r['expected']}"
        print(f"  {label:<30}{r['deducted']:>8}{r['expected']:>6}{verdict:>16}")

    print()
    print("  逐条看：")
    for r in rows:
        print(f"    {r['label']}：{r['seen']}")
    print()
    print("  → S1 完全没有防线，重复几次多扣几次（扣了 18）。")
    print("  → S2 串行跑看起来对（扣了 10），但它靠的是「查」和「改」之间没有别人插进来；")
    print("     这个前提在并发下不成立 —— 换个顺序就会破。")
    print("  → S3 串行也对，但它有一个「去重表写成功、业务没做」的崩溃窗口。")
    print("  → S4 只有唯一约束能真正兜住：重复消息撞主键，整个本地事务回滚。")
    print()


def r2_split_tx_crash():
    print("【R2 S3 的致命窗口：去重表已提交、业务还没做就崩了】")
    print("    场景：m1 正常处理完，接着处理 m2，在「标记完、改业务前」进程死掉。")
    print()

    reset_stock()
    consume_split_tx("m1")                        # 正常一条
    after_first = stock()
    r_crash = consume_split_tx("m2", crash_after_mark=True)   # 新消息，崩在标记后
    r_retry = consume_split_tx("m2")              # 消息重投
    q3 = stock()
    print(f"  S3 分两个事务：")
    print(f"    m1 处理完 → 库存 {after_first}")
    print(f"    m2 标记后崩溃 → {r_crash}")
    print(f"    m2 重投 → {r_retry}（去重表说处理过了，直接跳过）")
    print(f"    最终库存 {q3}，应为 {INIT_STOCK - 2} → {'✗ 永久少扣一次' if q3 != INIT_STOCK - 2 else '✓'}")
    print()

    reset_stock()
    consume_same_tx("m1")
    after_first = stock()
    r_crash = consume_same_tx("m2", crash_before_commit=True)
    r_retry = consume_same_tx("m2")
    q4 = stock()
    print(f"  S4 同事务：")
    print(f"    m1 处理完 → 库存 {after_first}")
    print(f"    m2 提交前崩溃 → {r_crash}（两件事一起回滚）")
    print(f"    m2 重投 → {r_retry}（正常扣减）")
    print(f"    最终库存 {q4}，应为 {INIT_STOCK - 2} → {'✓ 正确' if q4 == INIT_STOCK - 2 else '✗'}")
    print()
    print("  → S3 在崩溃后永久丢了 m2 的扣减：去重表说做过、业务其实没做，而且再也不会重做。")
    print("  → S4 崩溃时两件事一起回滚，重投时能正常做 —— 这就是「必须同事务」的原因。")
    print()


def r2b_check_then_act_race():
    print("【R2b 「先查再改」在交错执行下失效】")
    print("    两个消费者几乎同时收到同一条 m1，各自先查处理日志 —— 都查到「没有」。")
    print("    然后各自去改业务：谁也不会被拦住。")
    print()
    reset_stock()

    # 阶段一：两个消费者各自查（都看到"没处理过"）
    ca, cb = conn(), conn()
    seen_a = ca.execute("SELECT 1 FROM inbox_naive WHERE msg_id='m1'").fetchone()
    seen_b = cb.execute("SELECT 1 FROM inbox_naive WHERE msg_id='m1'").fetchone()
    print(f"  消费者 A 查到：{seen_a}（看到没处理过）")
    print(f"  消费者 B 查到：{seen_b}（看到没处理过）")
    ca.close(); cb.close()

    # 阶段二：两个消费者各自扣减（都以为自己该做）
    for who in ("A", "B"):
        c = conn()
        c.execute("BEGIN IMMEDIATE")
        c.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
        c.execute("COMMIT")
        c.close()
        print(f"  消费者 {who} 扣减：成功（没有唯一约束能拦住它）")

    # 阶段三：各自补处理日志（两条都能插进去，因为没有唯一约束）
    for who in ("A", "B"):
        c = conn()
        c.execute("INSERT INTO inbox_naive(msg_id, processed_at) VALUES('m1', ?)",
                  (time.time(),))
        c.close()

    q = stock()
    c = conn()
    rows = c.execute("SELECT COUNT(*) FROM inbox_naive WHERE msg_id='m1'").fetchone()[0]
    c.close()
    print(f"  处理日志里 m1 的行数 = {rows}（应为 1）")
    print(f"  最终库存扣减量 = {INIT_STOCK - q}（应为 1）")
    print()
    print("  → 朴素写法在并发下多扣一次，而且处理日志里留下两条「我也办过」的记录。")
    print("  → 对照 R1 的串行结果：S2 那栏是 ✓ —— 这就是「本地跑没问题、上线就重复扣」的成因。")
    print("  → 正解不是加锁，而是把 INSERT 放进同一个事务、并给 msg_id 加唯一约束（S4）。")
    print()


def r3_wrong_key():
    print("【R3 去重键选错：用「第几次投递」当键，等于没去重】")
    reset_stock()
    deliveries = ["m1", "m1", "m1", "m1"]
    for n, mid in enumerate(deliveries, start=1):
        c = conn()
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO inbox_bad VALUES(?,?,?)", (n, mid, time.time()))
        c.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
        c.execute("COMMIT")
        c.close()
    q = stock()
    c = conn()
    rows = c.execute("SELECT delivery_no, msg_id FROM inbox_bad").fetchall()
    c.close()
    print(f"  同一条消息 m1 被投递 4 次，去重表记录：{rows}")
    print(f"  库存扣减量 = {INIT_STOCK - q}（应为 1）")
    print()
    print("  → 每次投递都生成新的自增号，主键永远不冲突，去重表一行没少。")
    print("  → 去重键必须是「消息自己的身份」（发送方生成的 event_id / 业务键），")
    print("     不能是「这次投递的身份」（自增号、时间戳、消费者侧的序号）。")
    print()


def r4_table_growth():
    print("【R4 去重表也只涨不消】")
    reset_stock()
    marks = []
    for batch in range(1, 6):
        for i in range(100):
            consume_same_tx(f"b{batch}-m{i}")
        c = conn()
        n = c.execute("SELECT COUNT(*) FROM inbox").fetchone()[0]
        c.close()
        marks.append((batch, n))
    print(f"  {'批次':<8}{'inbox累计行数':>16}")
    for b, n in marks:
        print(f"  第{b}批{'':<6}{n:>16}")
    print()
    print("  → 与 outbox 一样：已处理的消息 id 也要按保留期清理，否则表无限增长。")
    print("  → 保留期取决于「消息最长可能延迟多久后重投」—— 短于这个值就会误判。")
    print()


def main():
    print("=" * 74)
    print("课 10 · M3  幂等消费与去重表")
    print(f"库文件：{DB}")
    print("=" * 74)
    print()
    setup()
    r1_four_ways()
    r2_split_tx_crash()
    r2b_check_then_act_race()
    r3_wrong_key()
    r4_table_growth()
    print("=" * 74)
    print("一句话：发件箱把「不丢」做到了，代价是把「可能重复」推给了消费端；")
    print("        去重表的唯一约束，才是把「至少一次」收成「实际一次」的那颗螺丝。")
    print("=" * 74)


if __name__ == "__main__":
    main()
