"""探针 4：*_with_http_info 才是真协程 + async_req 在异步包里的行为

探针 3 已证：
- 外层 list_namespaced_pod 是普通 def，转发到 *_with_http_info
- 412 个方法参数名与同步版完全一致

本课查：
1. *_with_http_info 在异步包里是不是真 async def
2. async_req=True 在异步包里会怎样（同步包返回 thread，异步包呢）
3. 顺带确认 ApiClient 的 pool_threads 是否还存在（课 9 说默认 1）
"""
import asyncio
import inspect

from kubernetes.client.api import core_v1_api as s
from kubernetes_asyncio.client.api import core_v1_api as a

M = "list_namespaced_pod_with_http_info"


async def in_loop():
    print("=== 1. *_with_http_info 的协程性 ===")
    af = getattr(a.CoreV1Api, M)
    sf = getattr(s.CoreV1Api, M)
    print("异步 iscoroutinefunction:", inspect.iscoroutinefunction(af))
    print("同步 iscoroutinefunction:", inspect.iscoroutinefunction(sf))
    print("异步源码首行:",
          inspect.getsource(af).splitlines()[0].strip()[:100])
    print("同步源码首行:",
          inspect.getsource(sf).splitlines()[0].strip()[:100])

    print()
    print("=== 2. async_req 在异步包里的处理 ===")
    a_src = inspect.getsource(af)
    for i, l in enumerate(a_src.splitlines()):
        if "async_req" in l:
            print(f"{i:4d}| {l.strip()[:130]}")

    print()
    print("=== 3. ApiClient pool_threads 是否还在 ===")
    from kubernetes_asyncio.client import ApiClient as AApiClient
    from kubernetes.client import ApiClient as SApiClient
    a_init = inspect.signature(AApiClient.__init__)
    s_init = inspect.signature(SApiClient.__init__)
    print("异步 ApiClient 参数:", list(a_init.parameters))
    print("同步 ApiClient 参数:", list(s_init.parameters))
    print("异步有 pool_threads:", "pool_threads" in a_init.parameters)
    print("同步有 pool_threads:", "pool_threads" in s_init.parameters)

    print()
    print("=== 4. 异步 ApiClient 源码里还有没有线程池 ===")
    src = inspect.getsource(AApiClient.__init__)
    for i, l in enumerate(src.splitlines()):
        if re_kw := [k for k in ("pool_threads", "ThreadPool", "apply_async",
                                 "async_req") if k in l]:
            print(f"{i:4d}| {re_kw} -> {l.strip()[:120]}")

    print()
    print("=== 5. 真跑一次：async_req=True 在异步包里会怎样 ===")
    from kubernetes_asyncio import config as aconfig
    await aconfig.load_kube_config()
    ac = AApiClient()
    api = a.CoreV1Api(ac)
    try:
        r = api.list_namespaced_pod("default", async_req=True)
        print("未 await 时 type:", type(r))
        print("iscoroutine    :", inspect.iscoroutine(r))
        if inspect.iscoroutine(r):
            r.close()
            print("已 close")
    except Exception as e:
        print("调用即异常:", type(e).__name__, e)

    # 真正 await 一次看结果
    try:
        r2 = api.list_namespaced_pod("default", async_req=True)
        res = await r2
        print("await 后 type  :", type(res))
        print("await 后 attr  :", [x for x in ("items", "metadata") if hasattr(res, x)])
    except Exception as e:
        print("await 失败:", type(e).__name__, str(e)[:200])

    await ac.close()


def main():
    asyncio.run(in_loop())


if __name__ == "__main__":
    main()
