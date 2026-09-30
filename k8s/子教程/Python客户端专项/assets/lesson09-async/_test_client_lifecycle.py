"""课 9 番外 · 实测 A：ApiClient 的生命周期与线程亲和性

课 9 未实测项的前置：写操作共享 client 之前，先搞清 client 能不能跨协程/跨线程用。

核验点（每条都给实测证据）：
A1. ApiClient 是否必须在 running loop 内实例化（探针已见 RuntimeError，此处固定为结论）
A2. 一个 ApiClient 能否被多个协程共用（课 9 已测 20/20 只读，此处复核）
A3. 跨线程（run_in_executor）复用同一个 ApiClient 会怎样 —— 这是"线程亲和性"关键
A4. api_client.close() 到底关了什么
"""
import asyncio
import concurrent.futures
import inspect
import os

from kubernetes_asyncio import client as aclient
from kubernetes_asyncio import config as aconfig

NS = os.environ.get("NS", "default")


async def a1_loop_required():
    print("=== A1. ApiClient 是否必须在 running loop 内实例化 ===")
    # 已在 running loop 内，直接实例化应成功
    try:
        ac = aclient.ApiClient()
        print("loop 内实例化: OK")
        await ac.close()
    except Exception as e:
        print("loop 内实例化失败:", type(e).__name__, e)
        return


def a1_outside_loop():
    try:
        aclient.ApiClient()
        return "loop 外实例化: 竟然 OK"
    except Exception as e:
        return f"loop 外实例化: {type(e).__name__}: {e}"


async def a2_shared_across_coros():
    print()
    print("=== A2. 单 ApiClient 多协程共用（只读）===")
    await aconfig.load_kube_config()
    async with aclient.ApiClient() as ac:
        api = aclient.CoreV1Api(ac)
        results = await asyncio.gather(
            *[api.list_namespaced_pod(NS, limit=1) for _ in range(20)],
            return_exceptions=True,
        )
        ok = sum(1 for r in results if not isinstance(r, BaseException))
        errs = [f"{type(r).__name__}: {str(r)[:80]}"
                for r in results if isinstance(r, BaseException)]
        print(f"20 个协程共用 1 个 ApiClient: 成功 {ok}/20")
        if errs:
            print("首个错误:", errs[0])


async def a3_cross_thread():
    print()
    print("=== A3. 跨线程复用同一 ApiClient（线程亲和性）===")
    await aconfig.load_kube_config()
    ac = aclient.ApiClient()
    api = aclient.CoreV1Api(ac)

    # 该 ApiClient 绑定在当前 loop 上
    loop = asyncio.get_running_loop()
    print("创建时 loop id:", id(loop))

    def blocking_call():
        """在工作线程里调用 api 方法（返回协程对象）"""
        try:
            coro = api.list_namespaced_pod(NS, limit=1)
            return ("协程对象已创建", type(coro).__name__)
        except Exception as e:
            return ("创建即失败", f"{type(e).__name__}: {str(e)[:120]}")

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        r1 = await loop.run_in_executor(ex, blocking_call)
    print("线程内创建协程:", r1)

    # 关键：在事件循环内创建协程，但让它在另一个 loop 里 await —— 更常见的误用
    # 这里测的是：把同一个 ApiClient 拿到另一个事件循环（新线程的新 loop）去跑
    def run_new_loop():
        async def inner():
            try:
                return await api.list_namespaced_pod(NS, limit=1)
            except Exception as e:
                return f"{type(e).__name__}: {str(e)[:160]}"
        try:
            new_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(new_loop)
            res = new_loop.run_until_complete(inner())
            new_loop.close()
            return res
        except Exception as e:
            return f"线程内新 loop 失败: {type(e).__name__}: {str(e)[:160]}"

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
        r2 = await loop.run_in_executor(ex, run_new_loop)
    if isinstance(r2, str):
        print("跨线程跨 loop 复用:", r2)
    else:
        print("跨线程跨 loop 复用: 竟然成功, type =", type(r2).__name__)

    await ac.close()


async def a4_close_semantics():
    print()
    print("=== A4. api_client.close() 关的是什么 ===")
    await aconfig.load_kube_config()
    ac = aclient.ApiClient()
    rc = ac.rest_client
    print("rest_client type      :", type(rc).__name__)
    conn = getattr(rc, "_connector", None) or getattr(rc, "connector", None)
    print("connector type        :", type(conn).__name__ if conn else None)
    if conn is not None:
        print("close 前 connector.closed:", getattr(conn, "closed", "n/a"))
        try:
            print("_session 存在         :", hasattr(rc, "_session"))
        except Exception:
            pass
    await ac.close()
    if conn is not None:
        print("close 后 connector.closed:", getattr(conn, "closed", "n/a"))

    # 关掉之后还能不能用？
    api = aclient.CoreV1Api(ac)
    try:
        await api.list_namespaced_pod(NS, limit=1)
        print("close 后仍可调用      : True（未做防护）")
    except Exception as e:
        print("close 后调用          :", type(e).__name__, str(e)[:100])


def main():
    print(a1_outside_loop())
    print()

    async def runner():
        await a1_loop_required()
        await a2_shared_across_coros()
        await a3_cross_thread()
        await a4_close_semantics()

    asyncio.run(runner())


if __name__ == "__main__":
    main()
