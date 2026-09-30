"""重试与指数退避：可复用的重试器 + 带重试的调谐 worker

立论（2026-09-29 实测，见 lessons/lesson-06-async4-*.md）：
  Q1 番外 1 的 worker 裸 except 后**丢弃对象** → 临时故障造成永久状态漂移
  Q2 错误分类：409/5xx/超时 → 重试；404/422/400 → 不重试
  Q3 天真重试（固定间隔+无上限）→ 队头阻塞，3 秒 30 次调用且 worker 被占死
  Q4 无 jitter 时 100 个对象**同一瞬间**重试（跨度 0.0000s）= 惊群

本文件提供：
  RetryPolicy   重试策略（分类 + 退避 + 上限）
  retry_async   可复用的重试执行器
  RetryQueue    带重试计数的工作队列（失败后延迟重入队，不阻塞 worker）
"""

import asyncio
import random
import time
from collections import defaultdict

from kubernetes_asyncio.client.rest import ApiException


# ---------------------------------------------------------------- 错误分类

def classify(exc):
    """把异常分类为 retryable / fatal / gone

    实测依据（2026-09-29）：
      409 Conflict  → retryable（重读最新 resourceVersion 后重写）
      5xx           → retryable（服务端暂时不可用）
      404 NotFound  → gone（对象已删除，重试无意义）
      422 / 400     → fatal（请求本身错，重试一万次也一样）
    """
    if isinstance(exc, ApiException):
        if exc.status == 404:
            return "gone"
        if exc.status in (409, 500, 502, 503, 504):
            # 409 只有在使用 replace（带 rv）时才是冲突；
            # 用 patch 的话 409 几乎不会出现（番外 1 已改用 patch）
            return "retryable"
        if exc.status in (400, 401, 403, 422):
            return "fatal"
        return "retryable" if exc.status >= 500 else "fatal"

    # 网络层：超时、连接重置都是可重试的
    if isinstance(exc, (asyncio.TimeoutError, TimeoutError)):
        return "retryable"
    if isinstance(exc, (ConnectionError, OSError)):
        return "retryable"

    return "fatal"        # 未知异常默认不重试（保守，避免放大）


# ---------------------------------------------------------------- 退避

def backoff_delay(attempt, base=0.1, cap=5.0, jitter="equal"):
    """指数退避 + jitter

    attempt 从 0 开始：base, base*2, base*4 ... 上限 cap

    jitter 模式（实测对比，2026-09-29）：
      none  : 精确 base*2^n            → 惊群（100 对象同一瞬间重试）
      full  : uniform(0, v)            → 最散，但可能等太久
      equal : v/2 + uniform(0, v/2)    → AWS 推荐，兼顾散度与下界
      decorrelated: 与上次的间隔相关   → 最平滑，但实现复杂

    默认 equal：实测第 3 次重试跨度 0.1991s（无 jitter 时为 0.0000s）
    """
    v = min(base * (2 ** attempt), cap)
    if jitter == "none":
        return v
    if jitter == "full":
        return random.uniform(0, v)
    if jitter == "decorrelated":
        # 需要外部传入上次延迟，这里退化为 equal
        return v / 2 + random.uniform(0, v / 2)
    return v / 2 + random.uniform(0, v / 2)      # equal（默认）


# ---------------------------------------------------------------- 重试器

class RetryPolicy:
    def __init__(self, max_attempts=5, base=0.1, cap=5.0,
                 jitter="equal", deadline=None):
        self.max_attempts = max_attempts
        self.base = base
        self.cap = cap
        self.jitter = jitter
        self.deadline = deadline          # 总时长上限（秒），防无限重试

    def delay(self, attempt):
        return backoff_delay(attempt, self.base, self.cap, self.jitter)


async def retry_async(fn, policy=None, stats=None, on_classify=None,
                      label=""):
    """执行 fn，按策略重试

    成功返回 fn() 的结果；**放弃时抛出最后一次异常**（由调用方分类处理）。

    ⚠️ 为什么放弃时要 raise 而不是返回 (None, False)：
       2026-09-29 实测 Q3 时踩到——初版返回 (None, False)，
       结果 worker 的 `except` 分支**永远走不到**，
       失败对象既不会被重入队也不会被记 dropped，直接静默丢失。
       返回"失败标志"会让调用方**忘记处理失败**，raise 则强迫它处理。

    ⚠️ 其他关键设计：
      1. 分类先行 —— gone/fatal 立即放弃，不浪费重试额度
      2. 次数 + 时间双重上限 —— 防止"慢速无限重试"
      3. 退避在**重试前**等待，而不是失败后立刻重试
    """
    policy = policy or RetryPolicy()
    stats = stats if stats is not None else defaultdict(int)
    start = time.monotonic()
    last = None

    for attempt in range(policy.max_attempts):
        try:
            r = await fn()
            if attempt > 0:
                stats[f"recovered_at_{attempt}"] += 1
            stats["attempts"] += attempt + 1
            return r                                   # 成功：直接返回结果
        except asyncio.CancelledError:
            raise                                  # 取消信号必须向上传播
        except Exception as e:
            last = e
            kind = classify(e)
            if on_classify:
                kind = on_classify(e, kind) or kind
            stats[f"class_{kind}"] += 1

            if kind in ("gone", "fatal"):
                stats[f"giveup_{kind}"] += 1
                raise                                  # 不可重试：抛出

            if attempt + 1 >= policy.max_attempts:
                stats["giveup_exhausted"] += 1
                raise                                  # 次数耗尽：抛出

            if policy.deadline and \
                    (time.monotonic() - start) > policy.deadline:
                stats["giveup_deadline"] += 1
                raise                                  # 超时：抛出

            d = policy.delay(attempt)
            stats["slept"] += 1
            stats["slept_seconds"] += d
            await asyncio.sleep(d)

    stats["giveup_exhausted"] += 1
    raise last


# ---------------------------------------------------------------- 带重试的队列

class RetryQueue:
    """工作队列 + 失败延迟重入队

    与番外 1 的 AsyncWorkQueueFixed 的差别：
      普通队列：worker 取 → 失败 → done → **对象消失**
      重试队列：worker 取 → 失败 → 延迟重入队（保留重试次数）

    ⚠️ 关键：worker **不负责等待退避**，退避期间 worker 去干别的活。
       天真实现里 worker 在重试循环里 sleep，会占死 worker（队头阻塞，实测 3 秒 30 次调用）。
    """

    def __init__(self, policy=None, max_requeues=8):
        self.policy = policy or RetryPolicy()
        self.max_requeues = max_requeues
        self._q = asyncio.Queue()
        self._pending = set()
        self._scheduled = set()       # 已安排延迟重入队、尚未到期的对象
        self._counts = defaultdict(int)
        self._delayed = []
        self.stats = defaultdict(int)
        self._task = None

    def add(self, name):
        if name not in self._pending and name not in self._scheduled:
            self._pending.add(name)
            self._q.put_nowait(name)

    async def get(self):
        return await self._q.get()

    def done(self, name):
        """对象**彻底处理完**（成功，或判定不可重试）→ 清除全部痕迹"""
        n = self._counts.pop(name, 0)
        self._pending.discard(name)
        self._scheduled.discard(name)
        if n:
            self.stats[f"done_after_{n}_retries"] += 1
        else:
            self.stats["done_first_try"] += 1

    def task_done(self, name):
        """本次**出队处理结束**，但对象可能还要重入队

        🚨 与 done() 的区别（这是 2026-09-29 修掉的核心缺陷）：
           done()      = 彻底结束，清空重试计数
           task_done() = 只是本次出队结束，**保留重试计数**

        原实现只有 done()，worker 在「重入队」路径上也会调到它，
        导致 _counts 被清零 → 上限 max_requeues 永远达不到
        → 失败对象**无限重试**（实测每对象 254 次，远超上限 4 次）。

        修复：重入队路径调 task_done()，只有真正放弃或成功才调 done()。
        """
        self._pending.discard(name)
        self.stats["task_done"] += 1

    async def requeue_after(self, name, delay):
        """延迟后重新入队（worker 不阻塞）

        🚨 缺陷修复（2026-09-29）：
           原实现里 _later 检查 `if name in self._pending`，
           但调用方 done() 已经 discard 掉了 name → 条件恒为 False
           → **重入队被静默吞掉**：requeued 计数 +1，对象却再也不出现。
           实测症状：requeued=4 但每对象只调用 1 次。

           修复：用独立的 _scheduled 集合标记"已安排重入队"，
           不依赖 pending（pending 语义是"当前在队列中/处理中"）。
        """
        n = self._counts[name] + 1
        if n > self.max_requeues:
            self.stats["dropped_max_requeues"] += 1
            self._pending.discard(name)
            self._scheduled.discard(name)
            return False
        self._counts[name] = n
        self.stats["requeued"] += 1
        self._scheduled.add(name)          # ← 标记：已安排重入队
        self.stats["inflight_requeue"] = len(self._scheduled)

        async def _later():
            try:
                await asyncio.sleep(delay)
                self._scheduled.discard(name)
                self._pending.add(name)
                self._q.put_nowait(name)
            except asyncio.CancelledError:
                self._scheduled.discard(name)

        t = asyncio.create_task(_later())
        self._delayed.append(t)
        return True

    def attempt_of(self, name):
        return self._counts.get(name, 0)

    def start(self):
        return self

    async def shutdown(self):
        for t in self._delayed:
            if not t.done():
                t.cancel()
        if self._delayed:
            await asyncio.gather(*self._delayed, return_exceptions=True)

    @property
    def inflight(self):
        return len(self._pending)


# ---------------------------------------------------------------- 带重试的 worker

async def reconcile_worker_retry(wid, v1, ns, queue, stats, sem, stop_event,
                                 policy=None, reconcile_fn=None, delay=0.0):
    """带重试的调谐 worker

    与番外 1 版本的差别：
      旧：except Exception: stats["errors"] += 1        ← 对象丢失
      新：分类 → 可重试则延迟重入队（worker 立刻去干别的）
    """
    from async_controller import reconcile_one
    reconcile_fn = reconcile_fn or reconcile_one
    policy = policy or RetryPolicy()

    while not stop_event.is_set():
        try:
            name = await asyncio.wait_for(queue.get(), timeout=0.3)
        except asyncio.TimeoutError:
            continue
        except asyncio.CancelledError:
            raise

        attempt = queue.attempt_of(name) if hasattr(queue, "attempt_of") else 0
        is_retry_q = isinstance(queue, RetryQueue)

        async def _do():
            return await reconcile_fn(v1, ns, name, stats, delay=delay)

        # 🚨 这里**故意不用 try/finally**（2026-09-29 修掉的缺陷）：
        #    Python 的 finally **在 continue 时也会执行**。
        #    原写法把 `queue.done(name)` 放在 finally 里，
        #    于是「重入队」分支的 continue 依然会走到 done() → 清空 _counts
        #    → max_requeues 上限永远达不到 → 失败对象无限重试
        #    （实测每对象 254 次，远超上限 4 次）。
        #
        #    正确做法：三条路径各自显式收尾。
        requeued = False
        try:
            async with sem:
                await retry_async(_do, policy, stats, label=name)
            stats["ok"] += 1
        except asyncio.CancelledError:
            raise
        except Exception as e:
            kind = classify(e)                 # 二次分类
            stats[f"worker_{kind}"] += 1
            if kind == "retryable" and is_retry_q:
                stats["failed_final"] += 1
                d = policy.delay(attempt)
                await queue.requeue_after(name, d)
                requeued = True                # 保留重试计数，不调 done()
            # gone / fatal：不重入队，走下面的 done() 彻底清除

        if requeued:
            if hasattr(queue, "task_done"):
                queue.task_done(name)          # 只结束本次出队
            stats["requeued"] += 1
        else:
            queue.done(name)                   # 彻底结束，清空计数
        stats["processed"] += 1
