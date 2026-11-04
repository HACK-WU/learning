#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 10 · 机制实验 1：双写的四种组合

一个下单请求要做两件事：
  (1) 往自己的库里写一行订单  —— 本地事务，一定成功或一定失败
  (2) 把「订单来了」告诉下游  —— 走消息通道，另一个系统

两个系统没有共享事务。本实验把「库」与「消息」各自的结果两两组合摆出来，
看清哪两格是坏的、坏得有多安静；再单独验证一个错觉：
把「发消息」这行代码塞进 with 事务块里，它并不会跟着一起回滚。

零第三方依赖。python3 m1_dual_write_matrix.py
"""

import atexit
import os
import random
import sqlite3
import tempfile

TMP = tempfile.mkdtemp(prefix="m1dw_")

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

DB = os.path.join(TMP, "order.db")

SENT = []             # 假消息通道：下游收到的消息
BROKER_DOWN = False   # 通道是否可达


def conn():
    # isolation_level=None：自动提交。本实验要精确控制"事务边界在哪"，
    # 不能让 sqlite3 模块替我们决定什么时候 BEGIN/COMMIT。
    c = sqlite3.connect(DB, timeout=5.0, isolation_level=None)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA busy_timeout=5000")
    return c


def reset():
    c = conn()
    c.execute("DROP TABLE IF EXISTS orders")
    c.execute("CREATE TABLE orders(id INTEGER PRIMARY KEY, sku TEXT, qty INTEGER CHECK(qty > 0))")
    c.close()
    SENT.clear()


def broker_send(msg):
    """假消息通道。抛异常 = 这次没送出去；正常返回 = 上游拿到了 ack。"""
    if BROKER_DOWN:
        raise ConnectionError("broker unreachable")
    SENT.append(msg)
    return True


def counts():
    c = conn()
    n = c.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    c.close()
    return n, len(SENT)


def write_order(oid, qty=1):
    c = conn()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders VALUES(?,?,?)", (oid, "A-1", qty))
        c.execute("COMMIT")
        return "ok"
    except sqlite3.IntegrityError:
        c.execute("ROLLBACK")
        return "fail"
    finally:
        c.close()


# ---------------------------------------------------------------- 四种组合
def c1():
    """库成 + 消息成：正常路径。"""
    reset()
    write_order(1)
    broker_send("order-created:1")


def c2():
    """库成 + 消息未成：commit 之后、发送之前，进程没了。"""
    reset()
    write_order(2)
    # 这一行根本没机会执行：进程被 kill / 发布被打断 / 电源掉了
    return "crash-before-send"


def c3():
    """库败 + 消息成：先发消息，再写库，写库这一步失败。

    真实对应场景：消息已投递给下游，本地事务在 commit 时撞约束 / 死锁 / 连接断。
    这里用 CHECK(qty>0) 违规来制造一次干净的写库失败。
    """
    reset()
    broker_send("order-created:3")     # 消息先出去了
    r = write_order(3, qty=0)          # 写库失败（qty 必须 > 0）
    return r


def c4():
    """库败 + 消息未成：正常失败路径，两边都没发生。"""
    reset()
    globals()["BROKER_DOWN"] = True
    try:
        broker_send("order-created:4")  # 通道不可用，抛异常
    except ConnectionError:
        pass
    finally:
        globals()["BROKER_DOWN"] = False
    r = write_order(4, qty=0)           # 写库也失败
    return r


def c5_send_inside_tx():
    """错觉：把发消息塞进 with 事务块，以为能跟着回滚。"""
    reset()
    c = conn()
    try:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT INTO orders VALUES(5,'A-1',1)")
        broker_send("order-created:5")     # 这一步不受 sqlite 事务管辖
        raise RuntimeError("写库失败（约束冲突 / 死锁 / 连接断）")
    except RuntimeError:
        c.execute("ROLLBACK")
    finally:
        c.close()


# ---------------------------------------------------------------- 放大
def amplified(n=500, crash_rate=0.05, broker_rate=0.08, ghost_rate=0.03, seed=10):
    """把 C2/C3 这类低频事件按比例注入，看绝对数量而不是百分比。

    crash_rate  : commit 之后、发送之前崩掉的概率  → 丢事件
    broker_rate : 消息通道临时不可用的概率          → 丢事件
    ghost_rate  : 先发消息、后写库且写库失败的概率  → 幽灵事件
    """
    rnd = random.Random(seed)
    for i in range(n):
        reset_light()
        oid = 10000 + i
        if rnd.random() < broker_rate:
            globals()["BROKER_DOWN"] = True
        try:
            if rnd.random() < crash_rate:
                write_order(oid)                     # 库进了，消息永远不会发
                STATS["lost_event"] += 1
                continue
            if rnd.random() < ghost_rate:
                broker_send(f"order-created:{oid}")  # 消息先走
                if write_order(oid, qty=0) != "ok":  # 库写失败（约束违规）
                    STATS["ghost_event"] += 1
                continue
            if write_order(oid) == "ok":
                try:
                    broker_send(f"order-created:{oid}")
                except ConnectionError:
                    STATS["lost_event"] += 1
        except ConnectionError:
            STATS["lost_event"] += 1
        finally:
            globals()["BROKER_DOWN"] = False


STATS = {"lost_event": 0, "ghost_event": 0}


def reset_light():
    """放大实验只清计数，不重建表（省时间，也让订单累计可见）。"""
    c = conn()
    c.execute("DELETE FROM orders")
    c.close()
    SENT.clear()


def main():
    print("=" * 74)
    print("课 10 · M1  双写的四种组合")
    print(f"库文件：{DB}")
    print("=" * 74)
    print()

    print("【R1 四种组合，逐格看】")
    print(f"{'组合':<26}{'订单行':>8}{'下游收到':>10}{'一致?':>8}")
    print("-" * 74)

    c1()
    n, s = counts()
    print(f"{'C1 库成 + 消息成':<26}{n:>8}{s:>10}{'✓':>8}")

    c2()
    n, s = counts()
    print(f"{'C2 库成 + 消息未成':<26}{n:>8}{s:>10}{'✗ 丢事件':>8}")

    c3()
    n, s = counts()
    print(f"{'C3 库败 + 消息成':<26}{n:>8}{s:>10}{'✗ 幽灵事件':>8}")

    c4()
    n, s = counts()
    print(f"{'C4 库败 + 消息未成':<26}{n:>8}{s:>10}{'✓':>8}")

    print()
    print("  四格里坏的两格，都在「一边成了、另一边没成」。")
    print("  注意 C2 和 C3 全程没有抛任何异常给调用方 —— 这是双写最要命的地方：")
    print("  库说成了、消息没发出去，日志里一片祥和。")
    print()

    print("【R2 错觉验证：把发消息塞进 with 事务块】")
    c5_send_inside_tx()
    n, s = counts()
    print(f"  订单行 = {n}（事务回滚了，库很干净）")
    print(f"  下游收到 = {s}（消息已经出去了，回不来了）")
    print(f"  → 结论：{'包在事务里也没用' if (n == 0 and s == 1) else '意外结果，需排查'}")
    print("  sqlite 的事务只管它自己的连接；broker_send 走的是网络，不在这个事务里。")
    print()

    print("【R3 放大：500 笔，commit 后崩溃 5%、通道抖动 8%、先发后写 3%】")
    globals()["STATS"] = {"lost_event": 0, "ghost_event": 0}
    amplified()
    total = 500
    bad = STATS["lost_event"] + STATS["ghost_event"]
    print(f"  丢事件（库有、下游不知道） = {STATS['lost_event']} 笔")
    print(f"  幽灵事件（下游知道、库没有） = {STATS['ghost_event']} 笔")
    print(f"  静默不一致合计 = {bad} 笔 / {total} 笔 = {bad / total * 100:.1f}%")
    print()
    print("  这几百笔里，有几笔会在监控上报警？答案是零。")
    print("  两边的系统都认为自己一切正常：库成功提交了，broker 没有报错。")
    print()
    print("=" * 74)
    print("一句话：双写的问题不是「有时会失败」，而是「失败了没人知道」。")
    print("=" * 74)


if __name__ == "__main__":
    main()
