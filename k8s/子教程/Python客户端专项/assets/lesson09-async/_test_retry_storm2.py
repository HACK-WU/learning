"""修正：惊群度量的测法错误

上一轮"最大同窗"恒等于 200（= 并发数 N），恒定不变 = 度量失效。
按铁律：数字异常先怀疑测量方法。

原因分析：
  - 每次 call 只 sleep 0.002s，整个实验 200 个协程在数毫秒内跑完
  - 分桶窗口 0.005s 相对于总时长过大 → 几乎所有请求落在同 1~2 个桶
  - 于是"最大同窗"恒等于 N，与重试策略无关 → 该指标当前无区分力

修正方向（两条，都要做）：
  M1. 让时间尺度有意义：把 sleep 拉到与真实网络往返相当（如 0.02s），
      并把桶宽缩小到 1ms 级别，使重试批次能被分开
  M2. 换一个不依赖绝对时间的度量：统计"重试请求的时间间隔分布"
      —— 惊群的本质是"重试请求扎堆"，即间隔趋近 0
      —— 用相邻重试间隔的中位数/最小值衡量，比桶计数更稳

同时补 M3：区分"首轮请求"与"重试请求"——
  惊群只有在看重试请求时才有意义（首轮齐发是业务行为，不是重试造成）
"""
import asyncio
import random
import statistics
import time
from dataclasses import dataclass, field


@dataclass
class FakeAPIServer:
    fail_rate: float = 0.7
    rtt: float = 0.02                       # 与真实往返相当
    calls: int = 0
    first_round: list = field(default_factory=list)   # 首轮
    retries: list = field(default_factory=list)       # 重试（第 2 次及以后）

    async def call(self, attempt: int):
        self.calls += 1
        t = time.perf_counter()
        (self.first_round if attempt == 0 else self.retries).append(t)
        await asyncio.sleep(self.rtt)
        if random.random() < self.fail_rate:
            raise RuntimeError("503")
        return "ok"


async def naive(srv, n=100, attempts=3):
    async def one():
        last = None
        for i in range(attempts):
            try:
                return await srv.call(i)
            except Exception as e:
                last = e
                if i < attempts - 1:
                    await asyncio.sleep(0.01)      # 固定间隔
        return last
    await asyncio.gather(*[one() for _ in range(n)], return_exceptions=True)


async def jittered(srv, n=100, attempts=3):
    async def one():
        last = None
        for i in range(attempts):
            try:
                return await srv.call(i)
            except Exception as e:
                last = e
                if i < attempts - 1:
                    base = 0.01 * (2 ** i)
                    await asyncio.sleep(random.uniform(0, base))
        return last
    await asyncio.gather(*[one() for _ in range(n)], return_exceptions=True)


def spread(ts):
    """重试请求的离散程度：相邻间隔的中位数（越大越分散 = 越好）"""
    if len(ts) < 2:
        return None, None
    s = sorted(ts)
    gaps = [b - a for a, b in zip(s, s[1:])]
    return statistics.median(gaps), min(gaps)


def peak_per_ms(ts, window=0.001):
    """按 1ms 窗口统计峰值（修正后的桶宽）"""
    if not ts:
        return 0
    from collections import Counter
    c = Counter(int(t / window) for t in ts)
    return max(c.values())


async def run(label, fn, n=100, seed=42):
    random.seed(seed)
    srv = FakeAPIServer()
    t0 = time.perf_counter()
    await fn(srv, n=n)
    dur = time.perf_counter() - t0

    med, mn = spread(srv.retries)
    print(f"  {label:14s} 总请求 {srv.calls:4d} "
          f"(首轮 {len(srv.first_round)}, 重试 {len(srv.retries)}) "
          f"耗时 {dur:5.3f}s")
    if med is not None:
        print(f"     重试间隔: 中位数 {med*1000:7.3f}ms  最小 {mn*1000:7.4f}ms  "
              f"1ms窗口峰值 {peak_per_ms(srv.retries):3d}")
    else:
        print("     无重试请求")
    return srv


async def main():
    print("=== M1/M2 修正后：惊群度量（N=100, p=0.7, rtt=20ms）===")
    print()
    await run("朴素(固定)", naive)
    await run("退避+jitter", jittered)

    print()
    print("=== M3 关键对照：只看重试请求（首轮齐发不算惊群）===")
    print("  判据：1ms 窗口峰值 / 重试总数 —— 越接近 1 表示越分散")
    for label, fn in (("朴素(固定)", naive), ("退避+jitter", jittered)):
        random.seed(42)
        srv = FakeAPIServer()
        await fn(srv, n=100)
        if srv.retries:
            ratio = peak_per_ms(srv.retries) / len(srv.retries)
            print(f"  {label:14s} 峰值/总数 = {ratio:.3f}  "
                  f"(重试 {len(srv.retries)} 个)")


if __name__ == "__main__":
    asyncio.run(main())
