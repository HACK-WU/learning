"""课 2 SDK 上手示例：用 Python 连接 SurrealDB 3.2.4。

演示三件事：
1. WebSocket 连接（长连接、有状态，支持 LIVE 查询与事务）
2. HTTP 连接（短连接、无状态，每个请求独立认证）
3. 会话与事务只在 WebSocket 上可用（HTTP/内嵌会抛 NotImplementedError）
"""

from surrealdb import Surreal

ENDPOINT_WS = "ws://127.0.0.1:8000"
ENDPOINT_HTTP = "http://127.0.0.1:8000"
AUTH = {"username": "root", "password": "root"}


def demo_ws():
    print("--- [1] WebSocket 连接 ---")
    with Surreal(ENDPOINT_WS) as db:
        db.use("learn", "shop")
        db.signin(AUTH)
        print("  已连接并认证")

        print("  服务端版本:", db.version())

        # 用 query 跑 SurrealQL，参数用 vars 传入（防注入）
        res = db.query(
            "CREATE product SET name = $name, price = $price;",
            {"name": "SDK Keyboard", "price": 459},
        )
        print("  新建记录:", res)

        rows = db.query("SELECT * FROM product ORDER BY price;")
        print("  全部商品:")
        for r in rows:
            print("   ", r["id"], r.get("name"), r.get("price"))


def demo_http():
    print("--- [2] HTTP 连接 ---")
    try:
        with Surreal(ENDPOINT_HTTP) as db:
            db.use("learn", "shop")
            db.signin(AUTH)
            rows = db.query("SELECT * FROM product LIMIT 2;")
            print("  HTTP 查询成功，返回", len(rows), "条")
    except Exception as e:
        print("  HTTP 连接失败:", type(e).__name__, e)


def demo_session_tx():
    print("--- [3] 会话与事务（仅 WebSocket）---")
    with Surreal(ENDPOINT_WS) as db:
        db.use("learn", "shop")
        db.signin(AUTH)
        try:
            session = db.new_session()
            session.use("learn", "shop")
            txn = session.begin_transaction()
            txn.query("CREATE product:tx_demo SET name = 'In Transaction', price = 1;")
            txn.commit()
            print("  事务提交成功")
            print("  验证:", db.query("SELECT * FROM product:tx_demo;"))
            session.close_session()
        except Exception as e:
            print("  事务失败:", type(e).__name__, e)

    print("--- [4] HTTP 上跑事务会发生什么 ---")
    try:
        with Surreal(ENDPOINT_HTTP) as db:
            db.use("learn", "shop")
            db.signin(AUTH)
            txn = db.begin_transaction()
            txn.query("SELECT 1;")
            txn.commit()
    except Exception as e:
        print("  预期报错:", type(e).__name__, "-", e)


def demo_embedded():
    print("--- [5] 内嵌模式（不需要服务端）---")
    try:
        with Surreal("mem://") as db:
            db.use("test", "test")
            print("  内嵌 mem:// 连接成功（root 免认证）")
            print("  写入:", db.query("CREATE t SET hello = 'world';"))
    except Exception as e:
        print("  内嵌模式失败:", type(e).__name__, e)


if __name__ == "__main__":
    demo_ws()
    print()
    demo_http()
    print()
    demo_session_tx()
    print()
    demo_embedded()
    print()
    print("=== ALL_SDK_DEMO_DONE ===")
