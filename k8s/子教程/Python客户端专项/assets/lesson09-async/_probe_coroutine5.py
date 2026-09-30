"""探针 5：默认路径怎么变成协程 + pool_threads 在异步包里到底用没用

探针 4 重大发现：
- 异步包 async_req=True 返回 multiprocessing.pool.ApplyResult，不能 await（照搬同步包残留）
- *_with_http_info 也是普通 def
- 异步 ApiClient 仍有 pool_threads=1 参数

本课查：
1. 默认（async_req 未传）路径为何返回 coroutine —— 谁在造协程
2. ApplyResult 是哪来的（异步包里还 import multiprocessing 吗）
3. pool_threads 在异步 ApiClient 里是否真被使用
"""
import inspect

from kubernetes_asyncio.client import ApiClient
from kubernetes_asyncio.client.api import core_v1_api as a


def main():
    print("=== 1. *_with_http_info 尾部：怎么返回的 ===")
    src = inspect.getsource(a.CoreV1Api.list_namespaced_pod_with_http_info)
    lines = src.splitlines()
    start = max(0, len(lines) - 45)
    for i, l in enumerate(lines[start:], start):
        if any(k in l for k in ("return", "self.api_client", "call_api",
                                "async_req", "pool")):
            print(f"{i:4d}| {l.rstrip()[:140]}")

    print()
    print("=== 2. __call_api 是不是协程 ===")
    f = getattr(ApiClient, "__call_api", None) or getattr(
        ApiClient, "_ApiClient__call_api", None)
    print("找到 __call_api:", f is not None)
    if f:
        print("iscoroutinefunction:", inspect.iscoroutinefunction(f))
        print("首行:",
              inspect.getsource(f).splitlines()[0].strip()[:120])

    print()
    print("=== 3. 异步包里 multiprocessing / ApplyResult 的来源 ===")
    import kubernetes_asyncio.client.api_client as ac_mod
    msrc = inspect.getsource(ac_mod)
    for i, l in enumerate(msrc.splitlines()):
        if any(k in l for k in ("import multiprocessing", "ApplyResult",
                                "ThreadPool", "pool.apply_async")):
            print(f"{i:4d}| {l.rstrip()[:140]}")

    print()
    print("=== 4. 异步 ApiClient.__init__ 完整源码（看 pool_threads 用没用）===")
    isrc = inspect.getsource(ApiClient.__init__)
    for i, l in enumerate(isrc.splitlines()):
        print(f"{i:4d}| {l.rstrip()[:140]}")

    print()
    print("=== 5. 异步包 api_client 里搜 'pool' 全部出现 ===")
    for i, l in enumerate(msrc.splitlines()):
        if "pool" in l.lower():
            print(f"{i:4d}| {l.rstrip()[:140]}")


if __name__ == "__main__":
    main()
