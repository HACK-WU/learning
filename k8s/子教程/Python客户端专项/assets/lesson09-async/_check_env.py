"""课 9 番外 开篇：环境核实

核验三件事：
1. kubernetes_asyncio / kubernetes / aiohttp 版本
2. 异步与同步 API 方法名是否仍完全同名（课 9 结论复议）
3. 集群可写
"""
import asyncio
import inspect

import kubernetes
import kubernetes_asyncio
from kubernetes_asyncio import client as aclient
from kubernetes import client as sclient


def main():
    print("=== 1. 版本 ===")
    print("kubernetes       :", kubernetes.__version__)
    print("kubernetes_asyncio:", getattr(kubernetes_asyncio, "__version__", "n/a"))
    import aiohttp
    print("aiohttp          :", aiohttp.__version__)

    print()
    print("=== 2. 方法名同名复议（课 9 结论：412 个完全同名）===")
    async_names = {n for n in dir(aclient.CoreV1Api) if not n.startswith("_")}
    sync_names = {n for n in dir(sclient.CoreV1Api) if not n.startswith("_")}
    print("async CoreV1Api 成员数:", len(async_names))
    print("sync  CoreV1Api 成员数:", len(sync_names))
    only_async = sorted(async_names - sync_names)
    only_sync = sorted(sync_names - async_names)
    print("仅异步有:", only_async)
    print("仅同步有:", only_sync)

    # 协程性检查：哪些是 coroutine function
    coros = [n for n in sorted(async_names)
             if inspect.iscoroutinefunction(getattr(aclient.CoreV1Api, n, None))]
    print("异步中协程方法数:", len(coros))

    print()
    print("=== 3. 三配置函数协程性（课 9 结论复议）===")
    from kubernetes_asyncio import config as aconfig
    for fn in ("load_kube_config", "load_incluster_config", "load_config"):
        f = getattr(aconfig, fn, None)
        if f is None:
            print(f"{fn:24s}: 不存在")
        else:
            print(f"{fn:24s}: coroutine={inspect.iscoroutinefunction(f)}")


if __name__ == "__main__":
    main()
