"""课 6 调谐循环的异步改写版（对照同步版 lessons/lesson-06-watch与informer.md）

同步版的三个结构限制，异步版要解决：
  1. watch 占满线程 → 想 watch 多种资源只能开多线程
  2. 调谐是 IO 密集（read + patch）→ 串行处理把时间浪费在等待上
  3. 多 worker 在同步下 = 多线程，受 GIL 限制（课 9 实测：加线程反而慢）

本文件提供：
  - AsyncWorkQueue（朴素去重，有坑）
  - AsyncWorkQueueFixed（对齐 client-go 语义）
  - AsyncInformer（async with w + async for）
  - reconcile_one（幂等 + patch）
  - AsyncController（组装 + 优雅退出）
"""
import asyncio
import time
from collections import defaultdict

import kubernetes_asyncio as ka
from kubernetes_asyncio.client import ApiClient, CoreV1Api
from kubernetes_asyncio.client.rest import ApiException


# ---------------------------------------------------------------- 工作队列

class AsyncWorkQueue:
    """v1：朴素去重

    add() 时若已在 _inflight 则直接丢弃；done() 才移除。

    🚨 坑：处理期间发生的变更会被丢弃。
       对象 X 正在被调谐（耗时 2 秒），期间 X 又变了 2 次 →
       两次 add(X) 都因 X 仍在 _inflight 而被丢掉 →
       done() 后 X 不再入队 → **最后那次变更被永久漏掉**。

    实测会演示这个丢失。
    """

    def __init__(self):
        self._q = asyncio.Queue()
        self._inflight = set()
        self.dropped = 0          # 被去重丢弃的次数
        self.added = 0

    def add(self, name):
        if name in self._inflight:
            self.dropped += 1
            return False
        self._inflight.add(name)
        self._q.put_nowait(name)
        self.added += 1
        return True

    async def get(self):
        return await self._q.get()

    def done(self, name):
        self._inflight.discard(name)

    def qsize(self):
        return self._q.qsize()

    async def join(self):
        """等待队列排空（供优雅退出使用）"""
        await self._q.join()

    def task_done(self):
        self._q.task_done()


class AsyncWorkQueueFixed:
    """v2：对齐 client-go workqueue 语义

    三个集合/阶段：
      _dirty      等待处理（在队列里）
      _processing 正在处理中
    add() 时：
      在 _dirty      → 丢弃（已排队，无需重复）
      在 _processing → 标记 _dirty，等 done() 后重新入队  ← 关键差异
    get() 时：从 _dirty 移到 _processing
    done() 时：若仍在 _dirty，说明处理期间又变了 → 重新入队
    """

    def __init__(self):
        self._q = asyncio.Queue()
        self._dirty = set()
        self._processing = set()
        self.dropped = 0
        self.added = 0
        self.requeued = 0

    def add(self, name):
        if name in self._dirty:
            self.dropped += 1
            return False
        if name in self._processing:
            # 正在处理 → 标记为 dirty，done() 后会重新入队
            self._dirty.add(name)
            self.added += 1
            return True
        self._dirty.add(name)
        self._q.put_nowait(name)
        self.added += 1
        return True

    async def get(self):
        name = await self._q.get()
        self._dirty.discard(name)
        self._processing.add(name)
        return name

    def done(self, name):
        self._processing.discard(name)
        if name in self._dirty:
            self._q.put_nowait(name)
            self.requeued += 1
            return True
        return False

    def qsize(self):
        return self._q.qsize()

    async def join(self):
        """等待队列排空（供优雅退出使用）"""
        await self._q.join()

    def task_done(self):
        self._q.task_done()


# ---------------------------------------------------------------- informer

class AsyncInformer:
    """异步 informer：async with w + async for

    与同步版 SimpleInformer 的差异只有：
      - list 要 await
      - watch 用 async with / async for
      - 入队用 await queue.add()
    业务语义（list-watch 两段式、推进 rv、410 回退）完全不变。
    """

    def __init__(self, list_fn, ns, queue, on_event=None):
        self.list_fn = list_fn
        self.ns = ns
        self.queue = queue
        self.on_event = on_event
        self.cache = {}
        self.rv = None
        self.stats = defaultdict(int)
        self.events = []
        self.fatal = None         # 记录致命错误，供外部检查

    async def _full_list(self):
        r = await self.list_fn(namespace=self.ns)
        self.cache.clear()
        for o in r.items:
            self.cache[o.metadata.name] = o
        self.rv = r.metadata.resource_version
        self.stats["relist"] += 1
        return r

    async def _handle(self, e):
        et, o = e["type"], e["object"]
        self.rv = o.metadata.resource_version      # 关键：每次推进 rv
        name = o.metadata.name
        self.stats[et.lower()] += 1
        self.events.append((et, name))
        if et in ("ADDED", "MODIFIED", "BOOKMARK"):
            self.cache[name] = o
            if et == "BOOKMARK":
                return None                        # BOOKMARK 只推进 rv，不入队
            return name
        if et == "DELETED":
            self.cache.pop(name, None)
            return name                            # 删除也要入队（清理下游）
        return None

    async def run(self, stop_event, duration=None,
                  timeout_seconds=2, request_timeout=5):
        r = await self._full_list()
        print(f"    [list] 全量同步 {len(r.items)} 个对象, rv={self.rv}")

        deadline = (time.time() + duration) if duration else None
        w = ka.watch.Watch()
        async with w:
            while not stop_event.is_set():
                if deadline and time.time() > deadline:
                    break
                try:
                    async for e in w.stream(
                        self.list_fn, namespace=self.ns,
                        resource_version=self.rv,
                        timeout_seconds=timeout_seconds,
                        _request_timeout=request_timeout,
                    ):
                        name = await self._handle(e)
                        if self.on_event:
                            await self.on_event(e)
                        if name:
                            # ⚠️ add 是同步方法，不能 await
                            #    若写成 `await self.queue.add(name)`，
                            #    add 会先执行（added+1），然后 await True 抛 TypeError，
                            #    异常在 async for 内传播 → informer 死亡，
                            #    且被 gather(return_exceptions=True) 静默吞掉
                            self.queue.add(name)
                        if stop_event.is_set():
                            break
                except ApiException as ex:
                    if ex.status == 410:
                        self.stats["410"] += 1
                        await self._full_list()
                        continue
                    self.stats["fatal"] += 1
                    self.fatal = f"{type(ex).__name__}: {ex}"
                    print(f"    [informer 致命] {self.fatal}")
                    raise
                except asyncio.CancelledError:
                    raise                      # 取消是正常退出，不算错误
                except (asyncio.TimeoutError, TimeoutError):
                    # stream 自然到期（timeout_seconds 到点）属正常轮转，
                    # 不是致命错误 —— 不能计入 stats，否则误报
                    continue
                except Exception as ex:
                    # 🚨 这里必须有：否则任何异常都会被
                    #    gather(return_exceptions=True) 静默吞掉，
                    #    informer 死了但主流程毫不知情
                    self.stats["fatal"] += 1
                    self.fatal = f"{type(ex).__name__}: {ex}"
                    print(f"    [informer 致命] {self.fatal}")
                    raise


# ---------------------------------------------------------------- 调谐

async def reconcile_one(v1, ns, name, stats, want_key="managed",
                        want_val="true", delay=0.0):
    """幂等调谐：缺标记才 patch，已对就什么都不做

    两个铁律（课 6 5.4 / 5.5）：
      - 用 patch 不用 replace（避开 409 风暴）
      - 先判断"是否已是我要的状态"，是就 return（避免自激振荡）
    """
    if delay:
        await asyncio.sleep(delay)

    try:
        obj = await v1.read_namespaced_config_map(name=name, namespace=ns)
    except ApiException as ex:
        if ex.status == 404:
            stats["gone"] += 1
            return
        raise

    data = obj.data or {}
    if data.get(want_key) == want_val:
        stats["no_op"] += 1
        return "no_op"

    body = {"data": {**data, want_key: want_val}}
    await v1.patch_namespaced_config_map(name=name, namespace=ns, body=body)
    stats["reconciled"] += 1
    return "reconciled"


async def reconcile_worker(wid, v1, ns, queue, stats, sem, stop_event,
                           delay=0.0):
    """单个调谐 worker：从队列取 → 调谐 → done"""
    while not stop_event.is_set():
        try:
            name = await asyncio.wait_for(queue.get(), timeout=0.3)
        except asyncio.TimeoutError:
            continue
        except asyncio.CancelledError:
            raise
        try:
            async with sem:
                await reconcile_one(v1, ns, name, stats, delay=delay)
        except Exception:
            stats["errors"] += 1
        finally:
            queue.done(name)
            stats["processed"] += 1


# ---------------------------------------------------------------- 控制器

class AsyncController:
    """把 informer + 队列 + N 个 worker 组装起来"""

    def __init__(self, api, ns, list_fn=None, workers=4, concurrency=10,
                 queue_cls=AsyncWorkQueue):
        self.api = api
        self.ns = ns
        self.v1 = CoreV1Api(api)
        self.list_fn = list_fn or self.v1.list_namespaced_config_map
        self.workers_n = workers
        self.queue = queue_cls()
        self.sem = asyncio.Semaphore(concurrency)
        self.stats = defaultdict(int)
        self.stop = asyncio.Event()
        self.informer = AsyncInformer(self.list_fn, ns, self.queue)
        self._tasks = []

    async def run(self, duration=None, reconcile_delay=0.0):
        self._tasks.append(
            asyncio.create_task(self.informer.run(self.stop, duration=duration))
        )
        for i in range(self.workers_n):
            self._tasks.append(
                asyncio.create_task(reconcile_worker(
                    i, self.v1, self.ns, self.queue, self.stats,
                    self.sem, self.stop, delay=reconcile_delay))
            )
        results = await asyncio.gather(*self._tasks, return_exceptions=True)
        # ⚠️ 不能只看 return_exceptions=True 就完事——
        #    它让异常不抛出，但你必须主动检查，否则等于静默
        for i, r in enumerate(results):
            if isinstance(r, Exception) and not isinstance(r, asyncio.CancelledError):
                self.stats["task_error"] += 1
                self.fatal = f"task[{i}] {type(r).__name__}: {r}"
                print(f"    [控制器] {self.fatal}")
        return results

    async def shutdown(self, graceful_timeout=2.0):
        """优雅退出

        🚨 实测结论：只 stop.set() **不够**。
        watch 卡在 `await` 网络读上，根本不会去检查 Event ——
        实测 timeout_seconds=10/30 时，set() 之后 13s / 33s 都不退出；
        只有 timeout_seconds=2 恰好赶上 stream 到期才"看起来生效"。

        所以正确做法是：
          1. set() 通知 worker 停止取新任务
          2. 给一点时间让在途调谐做完（graceful）
          3. cancel() 掉所有任务（这才是真正让 watch 醒来的动作）
          4. gather 回收
        """
        self.stop.set()

        # 等队列排空或在途任务完成
        try:
            await asyncio.wait_for(self.queue.join(),
                                   timeout=graceful_timeout)
        except (asyncio.TimeoutError, TimeoutError, AttributeError):
            pass

        for t in self._tasks:
            if not t.done():
                t.cancel()                    # ← 关键：只有 cancel 能唤醒 await
        results = await asyncio.gather(*self._tasks, return_exceptions=True)
        # ⚠️ 不能只看 return_exceptions=True 就完事——
        #    它让异常不抛出，但你必须主动检查，否则等于静默
        for i, r in enumerate(results):
            if isinstance(r, Exception) and not isinstance(r, asyncio.CancelledError):
                self.stats["task_error"] += 1
                self.fatal = f"task[{i}] {type(r).__name__}: {r}"
                print(f"    [控制器] {self.fatal}")
        return results
