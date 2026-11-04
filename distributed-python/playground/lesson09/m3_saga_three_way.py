"""M3：Saga 三段对照 —— 补偿被重复投递时，幂等性差在哪

真实 sqlite3 三个库 = 三个服务（订单 / 库存 / 支付）。

业务链路四步，按「可补偿 → 不可补偿」排列：
  1 建订单（补偿：取消）        可补偿
  2 扣库存（补偿：释放）        可补偿
  3 扣款  （补偿：退款）        可补偿
  4 发货  （补偿：做不到）      pivot，之后失败只能重试到底

三种客户端策略跑同一批请求、同一组失败点：
  S1 无 Saga                  ：任一步失败直接返回，前面提交的不管
  S2 Saga，补偿不幂等          ：补偿被重复投递时，第二次真的又执行一遍
  S3 Saga，补偿幂等（+ 语义锁） ：第二次投递识别为重复，直接跳过

"补偿被重复投递"是真实常态：调用方没收到 ack 就会重试，
而第一次其实已经成功了 —— 这就是至少一次投递的必然结果。
关键在去重键：重试带的是同一个业务键，不是"第几次投递"。

失败点是预先生成的一份固定清单，三种策略共用同一份 ——
否则各自消耗的随机流不同，"成功笔数"就没法横向比。

纯标准库，python3 直接跑。约 3 秒。
"""
import os
import random
import sqlite3
import tempfile
from collections import Counter
from contextlib import contextmanager

TMP = tempfile.mkdtemp(prefix="m3_")
DB = {k: os.path.join(TMP, f"{k}.db") for k in ("order", "stock", "pay")}
INIT_STOCK = 1000
N = 100
# 注入的失败概率（在纯标准库模拟的服务里"故障注入"）
P_STOCK, P_PAY, P_SHIP = 0.10, 0.30, 0.05


def conn(which):
    c = sqlite3.connect(DB[which], timeout=10.0)
    c.isolation_level = None
    return c


@contextmanager
def tx(which):
    """一个事务 = 一个服务的本地事务。

    关键在于 finally 里一定 close()：sqlite 的 BEGIN IMMEDIATE 如果在
    异常路径上没有释放，这个库的写锁就会一直挂在那儿，后面的写全变成
    「database is locked」。这是三库实验最容易踩的一个坑。
    """
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
    c.execute("CREATE TABLE comp_log(key TEXT PRIMARY KEY)")   # 库存服务的去重表
    c.close()

    c = conn("pay")
    c.execute("CREATE TABLE pays(id INTEGER PRIMARY KEY AUTOINCREMENT, "
              "order_id INT, amount INT, state TEXT)")
    c.execute("CREATE TABLE comp_log(key TEXT PRIMARY KEY)")   # 支付服务的去重表
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
    """预先生成"这一笔在哪一步失败"，三种策略共用。
    这样横向比较时，成功笔数、失败笔数完全相同，差别只剩补偿行为。"""
    rnd = random.Random(7)
    out = []
    for oid in reqs:
        out.append((oid,
                    rnd.random() < P_STOCK,
                    rnd.random() < P_PAY,
                    rnd.random() < P_SHIP))
    return out


# ---------------------------------------------------------------- 三个服务
def create_order(oid, status="CONFIRMED"):
    with tx("order") as c:
        c.execute("INSERT INTO orders VALUES(?,?,?,?)", (oid, "A-1", 1, status))


def cancel_order(oid):
    """补偿：删掉订单。天然幂等 —— 删不存在的行不报错，删两次结果一样。"""
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
    """补偿：把库存加回去。注意这里没有幂等保护。

    这是本实验最关键的一处：它不报错。你把同一条补偿投递两次，
    它会老老实实加两次 —— 「成功得过头」比失败更难发现。
    """
    with tx("stock") as c:
        c.execute("UPDATE stock SET qty=qty+? WHERE sku=?", (qty, sku))


def release_stock_idem(key, qty=1, sku="A-1"):
    """幂等补偿：先占去重键，占到了才动手。"""
    try:
        with tx("stock") as c:
            c.execute("INSERT INTO comp_log VALUES(?)", (key,))
            c.execute("UPDATE stock SET qty=qty+? WHERE sku=?", (qty, sku))
    except sqlite3.IntegrityError:
        return "duplicate-skipped"
    return "released"


def charge(oid, amount=100):
    with tx("pay") as c:
        c.execute("INSERT INTO pays(order_id,amount,state) VALUES(?,?,?)",
                  (oid, amount, "CHARGED"))


def refund(oid):
    """补偿：退款。它也不是幂等的，但它会「响」—— 第二次找不到可退的支付就报错。"""
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
        return "duplicate-skipped"
    return "refunded" if n else "nothing-to-do"


def ship(oid):
    """pivot：这一步没有技术补偿。"""
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
    refunded = c.execute("SELECT COUNT(*) FROM pays WHERE state='REFUNDED'").fetchone()[0]
    c.close()

    reserved = INIT_STOCK - stock
    return {
        "orders": orders,
        "order_qty": order_qty,
        "reserved": reserved,
        "charged": charged,
        "refunded": refunded,
        "dev": abs(reserved - order_qty),
        "consistent": (reserved == order_qty) and (charged == orders),
    }


# ---------------------------------------------------------------- S1
def run_no_saga(decisions):
    stats = Counter()
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
            stats["success"] += 1
        except RuntimeError:
            stats["fail"] += 1     # 没有补偿，前面已提交的就留在那儿了
    return stats


# ---------------------------------------------------------------- S2 / S3
def run_saga(decisions, idempotent, semantic_lock=False, dup_delivery=True):
    """dup_delivery=True 模拟"补偿 ack 丢失 → 调用方重试"，
    也就是同一条补偿消息被投递两次。去重键用业务键（订单号），
    两次投递带的是同一个键 —— 这才是真实重试的样子。"""
    stats = Counter()

    for oid, f_stock, f_pay, f_ship in decisions:
        done = []
        try:
            create_order(oid, "PENDING" if semantic_lock else "CONFIRMED")
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

            if semantic_lock:
                with tx("order") as c:
                    c.execute("UPDATE orders SET status='CONFIRMED' WHERE id=?", (oid,))
            stats["success"] += 1

        except RuntimeError:
            stats["fail"] += 1
            for kind, arg in reversed(done):
                deliveries = 2 if dup_delivery else 1
                for _ in range(deliveries):
                    try:
                        if kind == "pay":
                            r = (refund_idem(f"refund-{arg}", arg)
                                 if idempotent else "refunded")
                            if not idempotent:
                                refund(arg)
                        elif kind == "stock":
                            r = (release_stock_idem(f"release-{oid}", arg)
                                 if idempotent else "released")
                            if not idempotent:
                                release_stock(arg)
                        else:
                            cancel_order(arg)
                            r = "cancelled"
                        stats[f"comp:{r}"] += 1
                    except Exception:
                        stats["comp:error"] += 1
    return stats


def line(t):
    print(f"\n{'-' * 72}\n{t}\n{'-' * 72}")


def main():
    print("=" * 72)
    print("M3：Saga 三段对照（真实 sqlite3 三库）")
    print("=" * 72)
    print(f"临时目录：{TMP}")
    print(f"业务量 {N} 笔｜注入失败：库存 10% / 支付 30% / 发货 5%")
    print("失败点是同一份预生成清单，三种策略共用（横向可比）")
    print("补偿重复投递：模拟 ack 丢失后的重试，每条补偿投递 2 次（同一去重键）")

    reqs = list(range(1, N + 1))
    decisions = make_decisions(reqs)
    n_stock = sum(1 for d in decisions if d[1])
    n_pay = sum(1 for d in decisions if not d[1] and d[2])
    n_ship = sum(1 for d in decisions if not d[1] and not d[2] and d[3])
    print(f"\n失败清单：库存失败 {n_stock} 笔｜支付失败 {n_pay} 笔"
          f"｜发货失败 {n_ship} 笔｜全成功 {N - n_stock - n_pay - n_ship} 笔")

    init()

    s1 = run_no_saga(decisions)
    c1 = snapshot()
    line("【S1 无 Saga】任一步失败直接返回，前面提交的不管")
    print(f"  成功 {s1['success']} 笔｜失败 {s1['fail']} 笔")
    print(f"  订单 {c1['orders']} 笔｜库存扣了 {c1['reserved']}"
          f"｜支付成功 {c1['charged']}")
    print(f"  库存扣减量与订单量之差：{c1['dev']}（0 才一致）")
    print(f"  一致性：{'OK' if c1['consistent'] else '不一致'}"
          f"   ← 差的这 {c1['dev']} 笔就是「有单无货」")

    reset()
    s2 = run_saga(decisions, idempotent=False)
    c2 = snapshot()
    line("【S2 Saga】补偿不幂等，被重复投递 2 次")
    print(f"  成功 {s2['success']} 笔｜失败 {s2['fail']} 笔")
    print(f"  补偿投递明细：{dict((k, v) for k, v in s2.items() if str(k).startswith('comp'))}")
    print(f"  订单 {c2['orders']} 笔｜库存扣了 {c2['reserved']}"
          f"｜支付成功 {c2['charged']}")
    print(f"  库存扣减量与订单量之差：{c2['dev']}")
    print(f"  一致性：{'OK' if c2['consistent'] else '不一致'}")

    reset()
    s3 = run_saga(decisions, idempotent=True, semantic_lock=True)
    c3 = snapshot()
    line("【S3 Saga】补偿幂等（去重表）+ 语义锁，同样重复投递 2 次")
    print(f"  成功 {s3['success']} 笔｜失败 {s3['fail']} 笔")
    print(f"  补偿投递明细：{dict((k, v) for k, v in s3.items() if str(k).startswith('comp'))}")
    print(f"  订单 {c3['orders']} 笔｜库存扣了 {c3['reserved']}"
          f"｜支付成功 {c3['charged']}")
    print(f"  库存扣减量与订单量之差：{c3['dev']}")
    print(f"  一致性：{'OK' if c3['consistent'] else '不一致'}")

    line("三段对照（成功/失败笔数三行完全一致，差别只在补偿行为）")
    print(f"{'方案':<22}{'成功':<8}{'失败':<8}{'补偿错误':<10}{'库存偏差':<10}{'终态一致'}")
    for name, st, c in [("S1 无 Saga", s1, c1),
                        ("S2 补偿不幂等", s2, c2),
                        ("S3 补偿幂等", s3, c3)]:
        print(f"{name:<20}{st['success']:<8}{st['fail']:<8}"
              f"{st.get('comp:error', 0):<10}{c['dev']:<10}"
              f"{'是' if c['consistent'] else '否'}")

    print(f"\n要点一：S1 偏差 {c1['dev']}（少扣了：有单无货）")
    print(f"        S2 偏差 {c2['dev']}（多还了：库存被重复加回去）")
    print("        → 不幂等的补偿不是「少做了一点」，是「做过头了」，"
          "而且方向相反、量级更大")
    print(f"要点二：S2 里订单补偿被投递 {s2['comp:cancelled']} 次全部成功"
          "（DELETE 天然幂等），")
    print(f"        退款补偿第二次直接报错 {s2['comp:error']} 次（它「会响」），")
    print(f"        库存补偿第二次静默成功（它「不响」）—— 三种补偿三种命运，")
    print("        最难查的就是最后那种：不报错的那一种。")
    print("要点三：Saga 中途的中间态对外可见，本实验用 PENDING 语义锁标注。")


if __name__ == "__main__":
    main()
