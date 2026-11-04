"""应用实战 09：跨服务下单 —— 纵向对比三跳答案

三跳演进（对应应用实战 09 正文）：
  第 1 步：写死两个库，用 with 包 —— 本地事务假装能护住全部
  第 2 步：加总协调者，三本账一起点头 —— 2PC（强一致，代价锁 + 可能僵住）
  第 3 步：Saga，去掉协调者，错了补一笔 —— 最终一致（代价中间态可见 + 补偿要幂等）

每一跳都用同一份预生成失败清单跑同一批订单，横向可比。
最终输出一张"三个版本各自代价"的对照表。

纯标准库，python3 直接跑。约 5 秒。
"""
import os
import random
import sqlite3
import tempfile
from contextlib import contextmanager

TMP = tempfile.mkdtemp(prefix="app09_")
DB = {k: os.path.join(TMP, f"{k}.db") for k in ("order", "stock", "pay")}
INIT_STOCK = 1000
N = 100
P_STOCK, P_PAY, P_SHIP = 0.10, 0.30, 0.05


def conn(which):
    c = sqlite3.connect(DB[which], timeout=10.0)
    c.isolation_level = None
    return c


@contextmanager
def tx(which):
    c = conn(which)
    try:
        c.execute("BEGIN IMMEDIATE")
        yield c
        c.execute("COMMIT")
    except BaseException:
        try:
            c.execute("ROLLBACK")
        except sqlite3.Error:
            pass
        raise
    finally:
        c.close()


def init():
    for which in DB:
        c = conn(which)
        c.execute("PRAGMA journal_mode=WAL")
        c.close()
    c = conn("order")
    c.execute("CREATE TABLE orders(id INTEGER PRIMARY KEY, sku TEXT, qty INT, status TEXT)")
    c.close()
    c = conn("stock")
    c.execute("CREATE TABLE stock(sku TEXT PRIMARY KEY, qty INT)")
    c.execute("INSERT INTO stock VALUES('A-1', ?)", (INIT_STOCK,))
    c.execute("CREATE TABLE comp_log(key TEXT PRIMARY KEY)")
    c.close()
    c = conn("pay")
    c.execute("CREATE TABLE pays(id INTEGER PRIMARY KEY AUTOINCREMENT, "
              "order_id INT, amount INT, state TEXT)")
    c.execute("CREATE TABLE comp_log(key TEXT PRIMARY KEY)")
    c.close()


def reset():
    for t, sql in [("order", "DELETE FROM orders"),
                   ("stock", f"UPDATE stock SET qty={INIT_STOCK}"),
                   ("stock", "DELETE FROM comp_log"),
                   ("pay", "DELETE FROM pays"),
                   ("pay", "DELETE FROM comp_log")]:
        with tx(t) as c:
            c.execute(sql)


def make_decisions(reqs):
    rnd = random.Random(7)
    out = []
    for oid in reqs:
        out.append((oid,
                    rnd.random() < P_STOCK,
                    rnd.random() < P_PAY,
                    rnd.random() < P_SHIP))
    return out


# ---- 服务 ----
def create_order(oid, status="CONFIRMED"):
    with tx("order") as c:
        c.execute("INSERT INTO orders VALUES(?,?,?,?)", (oid, "A-1", 1, status))


def cancel_order(oid):
    with tx("order") as c:
        c.execute("DELETE FROM orders WHERE id=?", (oid,))


def reserve_stock(sku="A-1", qty=1):
    with tx("stock") as c:
        cur = c.execute("UPDATE stock SET qty=qty-? WHERE sku=? AND qty>=?",
                        (qty, sku, qty))
        ok = cur.rowcount == 1
    if not ok:
        raise RuntimeError("库存不足")


def release_stock(qty=1, sku="A-1"):
    with tx("stock") as c:
        c.execute("UPDATE stock SET qty=qty+? WHERE sku=?", (qty, sku))


def release_stock_idem(key, qty=1, sku="A-1"):
    try:
        with tx("stock") as c:
            c.execute("INSERT INTO comp_log VALUES(?)", (key,))
            c.execute("UPDATE stock SET qty=qty+? WHERE sku=?", (qty, sku))
    except sqlite3.IntegrityError:
        return False
    return True


def charge(oid, amount=100):
    with tx("pay") as c:
        c.execute("INSERT INTO pays(order_id,amount,state) VALUES(?,?,?)",
                  (oid, amount, "CHARGED"))


def refund(oid):
    with tx("pay") as c:
        cur = c.execute("UPDATE pays SET state='REFUNDED' WHERE order_id=? "
                        "AND state='CHARGED'", (oid,))
        n = cur.rowcount
    if n == 0:
        raise RuntimeError("无可退款的支付")


def refund_idem(key, oid):
    try:
        with tx("pay") as c:
            c.execute("INSERT INTO comp_log VALUES(?)", (key,))
            cur = c.execute("UPDATE pays SET state='REFUNDED' WHERE order_id=? "
                            "AND state='CHARGED'", (oid,))
            n = cur.rowcount
    except sqlite3.IntegrityError:
        return False
    return n > 0


def ship(oid):
    return True


def snapshot():
    c = conn("order")
    orders, order_qty = c.execute(
        "SELECT COUNT(*), COALESCE(SUM(qty),0) FROM orders").fetchone()
    c.close()
    c = conn("stock")
    stock = c.execute("SELECT qty FROM stock WHERE sku='A-1'").fetchone()[0]
    c.close()
    c = conn("pay")
    charged = c.execute("SELECT COUNT(*) FROM pays WHERE state='CHARGED'").fetchone()[0]
    c.close()
    reserved = INIT_STOCK - stock
    return {
        "orders": orders,
        "reserved": reserved,
        "charged": charged,
        "dev": abs(reserved - order_qty),
        "consistent": (reserved == order_qty) and (charged == orders),
    }


# ---- 三跳 ----
def step1_naive(decisions):
    """写死两库：with 包，无补偿。失败就留下脏数据。"""
    failed = 0
    for oid, f_stock, f_pay, f_ship in decisions:
        try:
            create_order(oid)
            if f_stock:
                raise RuntimeError("库存失败")
            reserve_stock()
            if f_pay:
                raise RuntimeError("支付失败")
            charge(oid)
            if f_ship:
                raise RuntimeError("发货失败")
            ship(oid)
        except RuntimeError:
            failed += 1
    return {"success": N - failed, "fail": failed}


def step2_2pc(decisions):
    """2PC：先问，都答 VOTE-COMMIT 才一起提交；否则全撤销。

    简化：把"问"实现成 detect 失败，都"可提交"才 commit。
    协调者崩溃/超时兜底的仿真详见 m2，这里聚焦三跳的代价对比。"""
    failed = 0
    for oid, f_stock, f_pay, f_ship in decisions:
        # 没有失败 → 全部可提交
        if not (f_stock or f_pay or f_ship):
            try:
                create_order(oid, "CONFIRMED")
                reserve_stock()
                charge(oid)
                ship(oid)
            except RuntimeError:
                failed += 1
        else:
            # 有失败：2PC 会在 prepare 阶段就发现"有人不能提交"→ 全部不提交
            failed += 1
    return {"success": N - failed, "fail": failed}


def step3_saga(decisions, idempotent=True):
    """Saga：逐步做，错了倒着补。idempotent 决定补的操作是否幂等。"""
    failed = 0
    for oid, f_stock, f_pay, f_ship in decisions:
        done = []
        try:
            create_order(oid, "PENDING")     # 语义锁：中间态可见但标注
            done.append(("order", oid))
            if f_stock:
                raise RuntimeError("库存失败")
            reserve_stock()
            done.append(("stock", 1))
            if f_pay:
                raise RuntimeError("支付失败")
            charge(oid)
            done.append(("pay", oid))
            if f_ship:
                raise RuntimeError("发货失败")
            ship(oid)
            with tx("order") as c:
                c.execute("UPDATE orders SET status='CONFIRMED' WHERE id=?", (oid,))
        except RuntimeError:
            failed += 1
            for kind, arg in reversed(done):
                try:
                    if kind == "pay":
                        refund_idem(f"refund-{arg}", arg) if idempotent else refund(arg)
                    elif kind == "stock":
                        release_stock_idem(f"release-{oid}", arg) if idempotent else release_stock(arg)
                    else:
                        cancel_order(arg)
                except Exception:
                    pass
    return {"success": N - failed, "fail": failed}


def main():
    print("=" * 76)
    print("应用实战 09：跨服务下单 —— 三跳方案的横向代价对比")
    print("=" * 76)
    print(f"临时目录：{TMP}")
    print(f"业务量 {N} 笔｜注入失败：库存 10% / 支付 30% / 发货 5%")
    print("失败点是同一份预生成清单，三跳共用（横向可比）\n")

    reqs = list(range(1, N + 1))
    decisions = make_decisions(reqs)
    init()

    # 第 1 跳：写死两库
    s1 = step1_naive(decisions)
    c1 = snapshot()
    print(f"【第 1 步：写死两库】成功 {s1['success']} / 失败 {s1['fail']}"
          f"｜偏差 {c1['dev']}（{'一致' if c1['consistent'] else '不一致：有单无货'}）")

    # 第 2 跳：2PC
    reset()
    s2 = step2_2pc(decisions)
    c2 = snapshot()
    print(f"【第 2 步：2PC 强一致】成功 {s2['success']} / 失败 {s2['fail']}"
          f"｜偏差 {c2['dev']}（{'一致' if c2['consistent'] else '不一致'}）"
          f"｜代价：锁 + 协调者单点（见 m2）")

    # 第 3 跳：Saga（幂等）
    reset()
    s3 = step3_saga(decisions, idempotent=True)
    c3 = snapshot()
    print(f"【第 3 步：Saga 幂等】成功 {s3['success']} / 失败 {s3['fail']}"
          f"｜偏差 {c3['dev']}（{'一致' if c3['consistent'] else '不一致'}）"
          f"｜代价：中间态可见 + 补偿须写对")

    print("\n" + "=" * 76)
    print("三跳横向对比（同一批 100 笔、同一组失败点）")
    print("=" * 76)
    print(f"{'方案':<24}{'成功':<8}{'失败':<8}{'终态偏差':<10}{'一致'}")
    rows = [("第 1 步：写死两库", s1, c1),
            ("第 2 步：2PC", s2, c2),
            ("第 3 步：Saga", s3, c3)]
    for name, st, c in rows:
        print(f"{name:<22}{st['success']:<8}{st['fail']:<8}{c['dev']:<10}"
              f"{'✓' if c['consistent'] else '✗'}")

    print('\n要点：第 1 步把所有"不一致"都藏着不报（偏差 8）；第 2 步用锁换取强一致'
          '（代价在 m2 的崩溃仿真）；第 3 步用补换取无锁（代价在补偿的幂等性与中间态可见）。')
    print('     没有免费的一致：要么在写之前问所有人（可能有人一直不回答、锁被钉住），')
    print('     要么写完后补（补的时候别人可能已经看见了这条中间态）。')


if __name__ == "__main__":
    main()
