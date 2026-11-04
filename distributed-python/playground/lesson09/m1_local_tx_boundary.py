"""M1：本地事务的边界到底在哪

三个对照，全部真实 sqlite3 数据库：
  R1 单库多表：能回滚
  R2 跨库两步：第二步失败，第一步已经落库，回滚不了
  R3 把两步包在同一个 with 里也没用（连接是绑库的）

纯标准库，python3 直接跑。
"""
import os
import sqlite3
import tempfile

TMP = tempfile.mkdtemp(prefix="m1_")
ORDER_DB = os.path.join(TMP, "order.db")
STOCK_DB = os.path.join(TMP, "stock.db")


def init():
    for path, ddl in [
        (ORDER_DB, "CREATE TABLE orders(id INTEGER PRIMARY KEY, sku TEXT, qty INT, status TEXT)"),
        (STOCK_DB, "CREATE TABLE stock(sku TEXT PRIMARY KEY, qty INT)"),
    ]:
        c = sqlite3.connect(path)
        c.execute(ddl)
        c.commit()
        c.close()
    c = sqlite3.connect(STOCK_DB)
    c.execute("INSERT INTO stock VALUES('A-1', 100)")
    c.commit()
    c.close()


def reset_order():
    c = sqlite3.connect(ORDER_DB)
    c.execute("DELETE FROM orders")
    c.commit()
    c.close()


def reset_stock(q=100):
    c = sqlite3.connect(STOCK_DB)
    c.execute("UPDATE stock SET qty=?", (q,))
    c.commit()
    c.close()


def count(table, path):
    c = sqlite3.connect(path)
    n = c.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    c.close()
    return n


def stock_qty():
    c = sqlite3.connect(STOCK_DB)
    q = c.execute("SELECT qty FROM stock WHERE sku='A-1'").fetchone()[0]
    c.close()
    return q


def line(t):
    print(f"\n{'-' * 72}\n{t}\n{'-' * 72}")


# ------------------------------------------------------------------ R1
def r1_single_db():
    line("R1 单库多表：一个事务能保护两张表（这才是本地事务的能力边界）")
    reset_order()
    c = sqlite3.connect(ORDER_DB)
    try:
        c.execute("BEGIN")
        c.execute("INSERT INTO orders VALUES(1,'A-1',2,'PENDING')")
        c.execute("INSERT INTO orders VALUES(2,'A-1',3,'PENDING')")
        raise RuntimeError("模拟业务校验失败")
    except RuntimeError as e:
        c.rollback()
        print(f"  抛出：{e}")
    c.close()
    print(f"  回滚后 orders 行数 = {count('orders', ORDER_DB)}   ← 两条插入都消失了")
    print("  → 一个事务能保护同一个库里的任意多张表")


# ------------------------------------------------------------------ R2
def r2_cross_db():
    line("R2 跨库两步：第一步已经 commit，第二步失败回不来")
    reset_order()
    reset_stock(100)

    order = sqlite3.connect(ORDER_DB)
    stock = sqlite3.connect(STOCK_DB)
    try:
        # 第一步：订单库，自己 commit 了
        order.execute("BEGIN")
        order.execute("INSERT INTO orders VALUES(1,'A-1',2,'PENDING')")
        order.commit()
        print("  第 1 步：订单已写入并 commit")

        # 第二步：库存库，失败
        stock.execute("BEGIN")
        stock.execute("UPDATE stock SET qty=qty-2 WHERE sku='A-1'")
        raise RuntimeError("库存服务超时")
    except RuntimeError as e:
        stock.rollback()
        print(f"  第 2 步：抛出 {e} → 库存已回滚")
    finally:
        order.close()
        stock.close()

    print(f"  结果：orders = {count('orders', ORDER_DB)} 行"
          f"（应为 0）｜ stock = {stock_qty()}（应为 100）")
    print("  → 订单留下了，库存没扣。一笔「有单无货」的脏数据")


# ------------------------------------------------------------------ R3
def r3_same_with():
    line("R3 把两步包进同一个 with 也没用：连接是绑库的，不是绑事务的")
    reset_order()
    reset_stock(100)

    order = sqlite3.connect(ORDER_DB)
    stock = sqlite3.connect(STOCK_DB)
    try:
        with order, stock:                    # 语法上像"一个事务"
            order.execute("INSERT INTO orders VALUES(1,'A-1',2,'PENDING')")
            stock.execute("UPDATE stock SET qty=qty-2 WHERE sku='A-1'")
            raise RuntimeError("第二段逻辑失败")
    except RuntimeError as e:
        print(f"  抛出：{e}")
    finally:
        order.close()
        stock.close()

    print(f"  结果：orders = {count('orders', ORDER_DB)} 行"
          f"｜ stock = {stock_qty()}")
    print('  → 两个都是 0 / 100，看起来"都回滚了"——')
    print("    但这只是因为两个写都在同一线程里、且没有任何一个先 commit。")
    print("    只要中间任何一步 commit 过（真实服务必然如此），就回不去了。")


# ------------------------------------------------------------------ R2b
def r2b_batch(n=200):
    line(f"R2b 放大到 {n} 笔：脏数据比例")
    reset_order()
    reset_stock(1000)
    dirty = 0
    for i in range(1, n + 1):
        order = sqlite3.connect(ORDER_DB)
        stock = sqlite3.connect(STOCK_DB)
        try:
            order.execute("BEGIN")
            order.execute("INSERT INTO orders VALUES(?,?,?,?)", (i, "A-1", 1, "PENDING"))
            order.commit()
            stock.execute("BEGIN")
            # 每 10 笔里有 1 笔在扣库存时失败
            if i % 10 == 0:
                raise RuntimeError("库存不足")
            stock.execute("UPDATE stock SET qty=qty-1 WHERE sku='A-1'")
            stock.commit()
        except RuntimeError:
            stock.rollback()
            dirty += 1
        finally:
            order.close()
            stock.close()

    print(f"  发出 {n} 笔，其中 {n // 10} 笔在第 2 步失败")
    print(f"  实际 orders 表行数 = {count('orders', ORDER_DB)}")
    print(f"  实际库存 = {stock_qty()}（应为 {1000 - n + n // 10}）")
    print(f"  → 有单无货的脏数据 {dirty} 笔，占比 {dirty / n * 100:.1f}%")
    print('  → 本地事务不是"不够强"，是它根本没覆盖到第二个库')


def main():
    print("=" * 72)
    print("M1：本地事务的边界（真实 sqlite3，两个独立数据库文件）")
    print("=" * 72)
    print(f"临时目录：{TMP}")
    init()
    r1_single_db()
    r2_cross_db()
    r3_same_with()
    r2b_batch()


if __name__ == "__main__":
    main()
