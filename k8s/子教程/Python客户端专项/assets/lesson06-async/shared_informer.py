"""SharedInformer：单条连接 watch 多资源（Python 侧自己实现）

课 6 §7.2 结论（本次实测确认）：
  - 每个 watch 独占一条 TCP 连接（n=1/2/4/8 → 连接 1/2/4/8）
  - Python 标准库没有 SharedInformer（client-go 概念）

本文件实现两种方案并对比：

  方案 A NaiveMultiInformer：每资源一个 informer（基线，连接数 = 资源数）
  方案 B SharedInformer    ：单 informer + 事件分发（连接数 = 1）

⚠️ 重要：方案 B **不是**用一条 TCP 连接 watch 多种资源 ——
   K8s watch API 的 path 是 /api/v1/namespaces/{ns}/configmaps?watch=true，
   一个 HTTP 请求只能指定一种资源，**协议上无法混watch**。

   真正的 SharedInformer 含义（对齐 client-go）：
     1. 同一资源的多个订阅者**共享**一条 watch 连接（避免重复 watch）
     2. 共享同一个本地缓存（避免 N 份内存）
   本文实现的是这个语义 —— "shared" 指的是**共享给多个消费者**，
   不是"一条连接看多种资源"。

   这点必须先讲清楚，否则读者会以为能省掉 N-1 条连接却省不掉。
"""
import asyncio
import time
from collections import defaultdict

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api
from kubernetes_asyncio.client.rest import ApiException

from async_controller import AsyncWorkQueueFixed, reconcile_one


# ---------------------------------------------------------------- 方案 B 核心

class ResourceKind:
    """一种资源的订阅配置"""

    def __init__(self, name, list_fn, handler=None):
        self.name = name
        self.list_fn = list_fn
        self.handler = handler          # async (event_type, obj) -> None
        self.cache = {}
        self.rv = None
        self.stats = defaultdict(int)
        self.subscribers = []           # 多个消费者


class SharedInformer:
    """共享 informer：一种资源一条 watch，多个消费者共享

    与「每消费者一个 informer」的差别：
        消费者数 N=3，资源数 M=2
          朴素：3*2 = 6 条 watch 连接、6 份缓存
          共享：M = 2 条 watch 连接、2 份缓存  ← 与消费者数无关

    这就是 client-go SharedInformer 的核心价值：
    **成本只随资源种类增长，不随消费者数量增长**。
    """

    def __init__(self, ns, kinds):
        self.ns = ns
        self.kinds = {k.name: k for k in kinds}
        self.stop = asyncio.Event()
        self.tasks = []
        self.fatal = None
        self.events = []
        self.stats = defaultdict(int)

    def subscribe(self, kind_name, handler):
        """消费者订阅某种资源"""
        k = self.kinds.get(kind_name)
        if k is None:
            raise KeyError(f"未注册的资源类型: {kind_name}")
        k.subscribers.append(handler)

    async def _dispatch(self, kind, et, obj):
        """分发给所有订阅者；单个订阅者异常不能影响其他订阅者"""
        for h in kind.subscribers:
            try:
                await h(et, obj)
            except asyncio.CancelledError:
                raise
            except Exception as ex:
                # 🚨 关键：一个消费者挂了不能拖垮整条 watch
                kind.stats["handler_error"] += 1
                print(f"    [订阅者异常] {kind.name}: "
                      f"{type(ex).__name__}: {ex}")

    async def _full_list(self, kind):
        r = await kind.list_fn(namespace=self.ns)
        kind.cache.clear()
        for o in r.items:
            kind.cache[o.metadata.name] = o
        kind.rv = r.metadata.resource_version
        kind.stats["relist"] += 1
        self.stats["relist"] += 1
        return r

    async def _watch_kind(self, kind):
        """单种资源的 watch 循环（list-watch 两段式）"""
        r = await self._full_list(kind)
        print(f"    [list:{kind.name}] {len(r.items)} 个对象, rv={kind.rv}")

        w = ka.watch.Watch()
        async with w:
            while not self.stop.is_set():
                try:
                    async for e in w.stream(
                        kind.list_fn, namespace=self.ns,
                        resource_version=kind.rv,
                        timeout_seconds=2,
                        _request_timeout=5,
                    ):
                        et, o = e["type"], e["object"]
                        kind.rv = o.metadata.resource_version
                        kind.stats[et.lower()] += 1
                        self.stats[et.lower()] += 1
                        self.events.append((kind.name, et, o.metadata.name))

                        if et == "BOOKMARK":
                            continue                    # 只推进 rv
                        if et == "DELETED":
                            kind.cache.pop(o.metadata.name, None)
                        else:
                            kind.cache[o.metadata.name] = o

                        await self._dispatch(kind, et, o)

                        if self.stop.is_set():
                            break
                except ApiException as ex:
                    if ex.status == 410:
                        kind.stats["410"] += 1
                        await self._full_list(kind)
                        continue
                    kind.stats["fatal"] += 1
                    self.fatal = f"{kind.name}: ApiException {ex.status}"
                    raise
                except asyncio.CancelledError:
                    raise
                except (asyncio.TimeoutError, TimeoutError):
                    continue                            # stream 到期，正常轮转
                except Exception as ex:
                    kind.stats["fatal"] += 1
                    self.fatal = f"{kind.name}: {type(ex).__name__}: {ex}"
                    raise

    async def start(self):
        for k in self.kinds.values():
            self.tasks.append(asyncio.create_task(self._watch_kind(k)))

    async def run(self, duration=None):
        await self.start()
        if duration:
            await asyncio.sleep(duration)
            await self.shutdown()
        else:
            await asyncio.gather(*self.tasks, return_exceptions=True)
        return self

    async def shutdown(self, graceful=1.0):
        self.stop.set()
        try:
            await asyncio.wait_for(
                asyncio.gather(*self.tasks, return_exceptions=True),
                timeout=graceful)
        except (asyncio.TimeoutError, TimeoutError):
            pass
        for t in self.tasks:
            if not t.done():
                t.cancel()
        return await asyncio.gather(*self.tasks, return_exceptions=True)

    @property
    def watch_count(self):
        """watch 连接数 = 资源种类数（与消费者数无关）"""
        return len(self.kinds)


# ---------------------------------------------------------------- 方案 A 基线

class NaiveMultiInformer:
    """朴素：每个消费者各自一个 informer

    成本 = 消费者数 × 资源种类数
    """

    def __init__(self, ns, api):
        self.ns = ns
        self.api = api
        self.stop = asyncio.Event()
        self.tasks = []
        self.stats = defaultdict(int)
        self.events = []

    async def _one(self, cid, kind_name, list_fn, handler):
        cache, rv = {}, None
        r = await list_fn(namespace=self.ns)
        for o in r.items:
            cache[o.metadata.name] = o
        rv = r.metadata.resource_version
        self.stats["relist"] += 1

        w = ka.watch.Watch()
        async with w:
            while not self.stop.is_set():
                try:
                    async for e in w.stream(
                        list_fn, namespace=self.ns,
                        resource_version=rv, timeout_seconds=2,
                        _request_timeout=5,
                    ):
                        et, o = e["type"], e["object"]
                        rv = o.metadata.resource_version
                        self.stats[et.lower()] += 1
                        self.events.append((f"c{cid}:{kind_name}", et,
                                            o.metadata.name))
                        if et == "BOOKMARK":
                            continue
                        if et == "DELETED":
                            cache.pop(o.metadata.name, None)
                        else:
                            cache[o.metadata.name] = o
                        try:
                            await handler(et, o)
                        except Exception as ex:
                            self.stats["handler_error"] += 1
                        if self.stop.is_set():
                            break
                except asyncio.CancelledError:
                    raise
                except (asyncio.TimeoutError, TimeoutError):
                    continue
                except Exception:
                    self.stats["fatal"] += 1
                    raise

    def add_consumer(self, cid, kind_name, list_fn, handler):
        self.tasks.append(
            asyncio.create_task(self._one(cid, kind_name, list_fn, handler)))

    async def run(self, duration=None):
        if duration:
            await asyncio.sleep(duration)
            await self.shutdown()
        else:
            await asyncio.gather(*self.tasks, return_exceptions=True)
        return self

    async def shutdown(self, graceful=1.0):
        self.stop.set()
        try:
            await asyncio.wait_for(
                asyncio.gather(*self.tasks, return_exceptions=True),
                timeout=graceful)
        except (asyncio.TimeoutError, TimeoutError):
            pass
        for t in self.tasks:
            if not t.done():
                t.cancel()
        return await asyncio.gather(*self.tasks, return_exceptions=True)

    @property
    def watch_count(self):
        return len(self.tasks)


# ---------------------------------------------------------------- 控制器

class SharedController:
    """基于 SharedInformer 的调谐控制器

    多个消费者（不同业务逻辑）共享同一条 watch：
      消费者1: 给 ConfigMap 打 managed 标记
      消费者2: 统计/审计（只读）
    """

    def __init__(self, api, ns, kinds):
        self.api = api
        self.ns = ns
        self.v1 = CoreV1Api(api)
        self.informer = SharedInformer(ns, kinds)
        self.queue = AsyncWorkQueueFixed()
        self.sem = asyncio.Semaphore(8)
        self.stats = defaultdict(int)
        self.audit = defaultdict(int)
        self._tasks = []

    def wire(self):
        """把消费者接到共享 informer 上"""

        async def reconciler(et, obj):
            """消费者1：入队调谐"""
            self.queue.add(obj.metadata.name)

        async def auditor(et, obj):
            """消费者2：只统计，不改对象"""
            self.audit[et] += 1

        for name in self.informer.kinds:
            self.informer.subscribe(name, reconciler)
            self.informer.subscribe(name, auditor)

    async def _worker(self, wid):
        while not self.informer.stop.is_set():
            try:
                name = await asyncio.wait_for(self.queue.get(), timeout=0.3)
            except asyncio.TimeoutError:
                continue
            except asyncio.CancelledError:
                raise
            try:
                async with self.sem:
                    await reconcile_one(self.v1, self.ns, name, self.stats)
            except Exception:
                self.stats["errors"] += 1
            finally:
                self.queue.done(name)
                self.stats["processed"] += 1

    async def run(self, duration=None, workers=3):
        self.wire()
        self.informer.tasks.append(
            asyncio.create_task(self.informer.run(duration)))
        for i in range(workers):
            self._tasks.append(asyncio.create_task(self._worker(i)))
        self._tasks.append(self.informer.tasks[-1])
        await asyncio.gather(*self._tasks, return_exceptions=True)
        return self

    async def shutdown(self, graceful=1.5):
        await self.informer.shutdown(graceful)
        for t in self._tasks:
            if not t.done():
                t.cancel()
        return await asyncio.gather(*self._tasks, return_exceptions=True)
