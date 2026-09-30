"""探针 2：异步方法为什么 iscoroutinefunction=False？

探针 1 在类上看到 function 且 iscoroutinefunction=False，与"能 await"矛盾。
按铁律先核验测法：读源码 + unwrap，搞清楚装饰器做了什么。
顺便核验：ApiClient 是否必须在 running loop 内实例化。
"""
import asyncio
import inspect

from kubernetes_asyncio import client as aclient

TARGET = "list_namespaced_pod"


async def in_loop():
    print("=== A. 在 running loop 内实例化 ===")
    try:
        ac = aclient.ApiClient()
        print("ApiClient() 实例化: OK ->", type(ac).__name__)
        api = aclient.CoreV1Api(ac)
        print("CoreV1Api(ac)     : OK")
    except Exception as e:
        print("失败:", type(e).__name__, e)
        return

    print()
    print("=== B. 实例上绑定方法的协程性 ===")
    f = getattr(api, TARGET)
    print("type               :", type(f))
    print("ismethod           :", inspect.ismethod(f))
    print("iscoroutinefunction:", inspect.iscoroutinefunction(f))
    print("__func__ iscoroutinefn:",
          inspect.iscoroutinefunction(getattr(f, "__func__", None)))

    print()
    print("=== C. 有没有被包装（__wrapped__ / unwrap）===")
    raw = getattr(f, "__func__", f)
    print("has __wrapped__    :", hasattr(raw, "__wrapped__"))
    try:
        unwrapped = inspect.unwrap(raw)
        print("unwrap 后同名?     :", unwrapped is raw)
        print("unwrap 后 iscoro   :", inspect.iscoroutinefunction(unwrapped))
        print("unwrap 后 qualname :", getattr(unwrapped, "__qualname__", None))
    except Exception as e:
        print("unwrap 失败:", type(e).__name__, e)

    print()
    print("=== D. 源码前 25 行 ===")
    try:
        src = inspect.getsource(raw)
        for i, line in enumerate(src.splitlines()[:25], 1):
            print(f"{i:3d}| {line}")
    except Exception as e:
        print("取源码失败:", type(e).__name__, e)

    print()
    print("=== E. 决定性问题：调用后是不是 coroutine？===")
    try:
        res = api.list_namespaced_pod("default")
        print("调用返回 type        :", type(res))
        print("iscoroutine(result)  :", inspect.iscoroutine(res))
        print("isawaitable(result)  :", inspect.isawaitable(res))
        print("有 send 方法(asyncio):", hasattr(res, "send"))
        if inspect.isawaitable(res):
            res.close()
            print("已 close 未 await 的协程（避免 warning）")
    except Exception as e:
        print("调用失败:", type(e).__name__, e)

    print()
    print("=== F. 用 isawaitable 重新统计协程方法数 ===")
    n_awaitable = 0
    n_plain_fn = 0
    for n in dir(aclient.CoreV1Api):
        if n.startswith("_"):
            continue
        v = getattr(aclient.CoreV1Api, n, None)
        if inspect.iscoroutinefunction(v):
            n_awaitable += 1
        elif inspect.isfunction(v):
            n_plain_fn += 1
    print("iscoroutinefunction=True 的:", n_awaitable)
    print("普通 function 的          :", n_plain_fn)

    print()
    print("=== G. 那 412 个的名字到底怎么数出来的（课 9 口径）===")
    a = {n for n in dir(aclient.CoreV1Api) if not n.startswith("_")}
    from kubernetes import client as sclient
    s = {n for n in dir(sclient.CoreV1Api) if not n.startswith("_")}
    print("async 非 dunder:", len(a), " sync 非 dunder:", len(s))
    print("差集为空      :", a - s == set() and s - a == set())

    await ac.close()


def main():
    print("=== 0. loop 外实例化（对照）===")
    try:
        aclient.ApiClient()
        print("loop 外实例化: 竟然 OK")
    except Exception as e:
        print("loop 外实例化失败:", type(e).__name__, ":", e)
    print()
    asyncio.run(in_loop())


if __name__ == "__main__":
    main()
