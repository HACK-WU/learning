"""课 9 番外 · 实测 D：重试风暴（未实测项 3）

课 9 未实测：并发失败后的重试放大效应。

"重试风暴"定义：后端已出问题 → 每个客户端独立重试 → 请求量被放大 N 倍
 → 后端更糟 → 更多重试（正反馈雪崩）。

设计（关键：必须能观测"放大倍数"，否则只是讲故事）：
  D1. 基线：无重试，注入失败率 p，记录总请求数
  D2. 朴素重试（固定 3 次 + 无退避 + 无 jitter）：同条件，记录总请求数
  D3. 指数退避 + jitter：同条件，记录总请求数
  对比三者"打到后端的请求总量"与"完成耗时"

注入方式：不依赖真实 429（本机打不出），用**可注入的故障代理**语义 ——
在业务函数外包一层 fake apiserver，按 p 概率返回 503。
（这是标准做法：测重试策略用注入故障，不必真压垮后端）

同时观测"惊群"：并发 N 个同时失败 → 重试是否在同一时刻齐发
（课 6 番外 4 已测 jitter 对惊群的作用，此处在"并发"语境下复核）
"""
import asyncio
import random
import time
from collections import Counter
from dataclasses import dataclass, field


@dataclass
class FakeAPIServer:
    """可注入故障的假 apiserver，统计打到后端的请求量"""
    fail_rate: float = 0.5
    calls: int = 0
    timestamps: list = field(default_factory=list)

    async def call(self):
        self.calls += 1
        self.timestamps.append(time.perf_counter())
        await asyncio.sleep(0.002)          # 模拟一次网络往返
        if random.random() < self.fail_rate:
            raise RuntimeError("503 Service Unavailable")
        return "ok"


async def no_retry(srv, n=200):
    """D1 基线：不重试"""
    t0 = time.perf_counter()
    rs = await asyncio.gather(*[srv.call() for _ in range(n)],
                              return_exceptions=True)
    dt = time.perf_counter() - t0
    ok = sum(1 for r in rs if r == "ok")
    return srv.calls, ok, dt


async def naive_retry(srv, n=200, attempts=3):
    """D2 朴素重试：固定次数，无退避无 jitter"""

    async def one():
        last = None
        for i in range(attempts):
            try:
                return await srv.call()
            except Exception as e:
                last = e
                if i < attempts - 1:
                    await asyncio.sleep(0.01)   # 固定间隔（无退避）
        return last

    t0 = time.perf_counter()
    rs = await asyncio.gather(*[one() for _ in range(n)],
                              return_exceptions=True)
    dt = time.perf_counter() - t0
    ok = sum(1 for r in rs if r == "ok")
    return srv.calls, ok, dt


async def backoff_jitter_retry(srv, n=200, attempts=3):
    """D3 指数退避 + full jitter"""

    async def one():
        last = None
        for i in range(attempts):
            try:
                return await srv.call()
            except Exception as e:
                last = e
                if i < attempts - 1:
                    base = 0.01 * (2 ** i)
                    await asyncio.sleep(random.uniform(0, base))  # full jitter
        return last

    t0 = time.perf_counter()
    rs = await asyncio.gather(*[one() for _ in range(n)],
                              return_exceptions=True)
    dt = time.perf_counter() - t0
    ok = sum(1 for r in rs if r == "ok")
    return srv.calls, ok, dt


def thundering_herd(ts, window=0.005):
    """统计重试是否齐发：把时间戳按窗口分桶，返回最大桶内数量"""
    if not ts:
        return 0
    buckets = Counter(int(t / window) for t in ts)
    return max(buckets.values())


async def run_case(label, fn, fail_rate, n=200):
    random.seed(42)
    srv = FakeAPIServer(fail_rate=fail_rate)
    calls, ok, dt = await fn(srv)
    herd = thundering_herd(srv.timestamps)
    amplification = calls / n
    print(f"  {label:26s} 后端请求 {calls:5d} (放大 {amplification:5.2f}x) "
          f"成功 {ok:4d}/{n}  耗时 {dt:6.3f}s  最大同窗 {herd:4d}")
    return amplification, ok, herd


async def main():
    print("=== 重试风暴对比（注入失败率 p=0.5，并发 N=200）===")
    print("  放大倍数 = 打到后端的请求数 / 业务请求数（>1 即放大）")
    print()
    await run_case("D1 无重试", lambda s: no_retry(s), 0.5)
    await run_case("D2 朴素重试(3次/固定)", lambda s: naive_retry(s), 0.5)
    await run_case("D3 退避+jitter(3次)", lambda s: backoff_jitter_retry(s), 0.5)

    print()
    print("=== 失败率更高时（p=0.9，模拟后端已崩）===")
    await run_case("D1 无重试", lambda s: no_retry(s), 0.9)
    await run_case("D2 朴素重试(3次/固定)", lambda s: naive_retry(s), 0.9)
    await run_case("D3 退避+jitter(3次)", lambda s: backoff_jitter_retry(s), 0.9)

    print()
    print("=== 重试次数加码（p=0.9，attempts=5）===")
    await run_case("D2 朴素(5次)", lambda s: naive_retry(s, attempts=5), 0.9)
    await run_case("D3 退避+jitter(5次)",
                   lambda s: backoff_jitter_retry(s, attempts=5), 0.9)

    print()
    print("=== 关键观测：并发下的惊群（同时刻齐发）===")
    print("  最大同窗数越大 = 重试越集中 = 越容易二次打垮后端")
    for label, fn in (("朴素(固定间隔)", lambda s: naive_retry(s)),
                      ("退避+jitter", lambda s: backoff_jitter_retry(s))):
        random.seed(7)
        srv = FakeAPIServer(fail_rate=0.7)
        await fn(srv)
        print(f"  {label:16s} 后端请求 {srv.calls:5d}, "
              f"最大同窗 {thundering_herd(srv.timestamps):4d}")


if __name__ == "__main__":
    asyncio.run(main())
