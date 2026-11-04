"""M4：四种限流算法的真实差异 —— 同一条到达序列，四种放行结果。

为什么必须四种一起跑：单看某一种"能限住"毫无信息量，差异只在同一个
到达序列上对比才能看见。

四种：
  1. 固定窗口（fixed window）      —— 窗口边界双倍放行
  2. 滑动窗口日志（sliding log）    —— 精确但存全部时间戳
  3. 滑动窗口计数（sliding counter） —— 加权近似，省内存
  4. 令牌桶（token bucket）         —— 允许突发到桶容量，长期速率受控

到达序列刻意造两个陷阱：
  · 跨越窗口边界的一串请求（暴露固定窗口的双倍问题）
  · 一段先静默再突发的流量（暴露漏桶/令牌桶对突发的不同态度）
"""
import time


class FixedWindow:
    """固定窗口：窗口按绝对时间对齐（如整秒 / 整分钟重置），桶内计数到 limit 就拒。

    注意 aligned=True 与 False 的差别很关键：
      aligned=True  → 窗口边界固定在 0s/1s/2s…（生产中"每分钟重置"的常见实现）
      aligned=False → 窗口从本窗口第一个请求开始计时（自己实现时容易写成这样）
    只有 aligned=True 才会出现经典的"边界双倍"问题。
    """

    def __init__(self, limit, window, aligned=True):
        self.limit, self.window = limit, window
        self.aligned = aligned
        self.window_id = None
        self.start = None
        self.count = 0

    def allow(self, now):
        if self.aligned:
            wid = int(now // self.window)
            if wid != self.window_id:
                self.window_id, self.count = wid, 0
        else:
            if self.start is None or now >= self.start + self.window:
                self.start, self.count = now, 0
        if self.count < self.limit:
            self.count += 1
            return True
        return False


class SlidingLog:
    """滑动窗口日志：保留窗口内每个通过的请求时间戳，精确计数。"""

    def __init__(self, limit, window):
        self.limit, self.window = limit, window
        self.log = []

    def allow(self, now):
        self.log = [t for t in self.log if t > now - self.window]
        if len(self.log) < self.limit:
            self.log.append(now)
            return True
        return False


class SlidingCounter:
    """滑动窗口计数：只存当前窗口与上一窗口的计数，按重叠比例加权。"""

    def __init__(self, limit, window):
        self.limit, self.window = limit, window
        self.cur_start = None
        self.cur = 0
        self.prev = 0

    def allow(self, now):
        if self.cur_start is None:
            self.cur_start, self.cur, self.prev = now, 0, 0
        while now >= self.cur_start + self.window:
            self.cur_start += self.window
            self.prev, self.cur = self.cur, 0
        elapsed = now - self.cur_start
        weight = (self.window - elapsed) / self.window
        estimated = self.prev * weight + self.cur
        if estimated < self.limit:
            self.cur += 1
            return True
        return False


class TokenBucket:
    """令牌桶：按 rate 匀速补令牌，桶容量 burst。空闲攒下的令牌可一次用完。"""

    def __init__(self, rate, burst):
        self.rate, self.burst = rate, burst
        self.tokens = burst
        self.last = None

    def allow(self, now, cost=1):
        if self.last is None:
            self.last = now
        self.tokens = min(self.burst, self.tokens + (now - self.last) * self.rate)
        self.last = now
        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False


def play(name, limiter, arrivals, label=""):
    """按给定的到达时刻序列逐条判定，打印放行/拒绝的分布。"""
    results = []
    for t in arrivals:
        ok = limiter.allow(t)
        results.append((t, ok))
    passed = [t for t, ok in results if ok]
    # 按 100ms 分桶看放行分布，能直观看出"边界双倍"和"突发"
    buckets = {}
    for t in passed:
        k = int(t * 10) / 10
        buckets[k] = buckets.get(k, 0) + 1
    dist = "  ".join(f"{k:.1f}s:{v}" for k, v in sorted(buckets.items()))
    print(f"  {name:<22}{label:<10}通过 {len(passed):>3} / {len(arrivals):<3}｜{dist}")
    return len(passed)


def main():
    print("=" * 96)
    print("陷阱一：请求跨越窗口边界 —— 每 1.0s 窗口限 10 次，但流量在边界两侧各来 10 次")
    # 0.90~0.99s 来 10 次，1.00~1.09s 又来 10 次：真实间隔仅 200ms，共 20 次
    arrivals = [0.90 + i * 0.01 for i in range(10)] + \
               [1.00 + i * 0.01 for i in range(10)]
    print(f"  到达：0.90-0.99s 十次，1.00-1.09s 十次（200ms 内共 20 次）")
    print()
    play("固定窗口(绝对对齐)", FixedWindow(10, 1.0, aligned=True), arrivals)
    play("固定窗口(首请求起算)", FixedWindow(10, 1.0, aligned=False), arrivals)
    play("滑动窗口日志", SlidingLog(10, 1.0), arrivals)
    play("滑动窗口计数", SlidingCounter(10, 1.0), arrivals)
    play("令牌桶 rate=10/s burst=10", TokenBucket(10, 10), arrivals)

    print("\n" + "=" * 96)
    print("陷阱二：先静默 2 秒再突发 20 次 —— 看各算法对『攒下来的额度』怎么处理")
    arrivals2 = [3.0 + i * 0.005 for i in range(20)]
    print(f"  到达：2.0s 内无请求，随后 100ms 内来 20 次")
    print()
    play("固定窗口(绝对对齐)", FixedWindow(10, 1.0), arrivals2)
    play("滑动窗口日志", SlidingLog(10, 1.0), arrivals2)
    play("滑动窗口计数", SlidingCounter(10, 1.0), arrivals2)
    play("令牌桶 rate=10/s burst=10", TokenBucket(10, 10), arrivals2)
    print()
    play("令牌桶 rate=10/s burst=20", TokenBucket(10, 20), arrivals2,
         "（大桶）")

    print("\n" + "=" * 96)
    print("陷阱三：稳定超额流量（每秒 20 次，持续 3 秒）—— 看长期速率是否真的被限住")
    arrivals3 = [i * 0.05 for i in range(60)]
    print(f"  到达：每 50ms 一次，共 60 次（= 20/s，限额 10/s）")
    print()
    play("固定窗口(绝对对齐)", FixedWindow(10, 1.0), arrivals3)
    play("滑动窗口日志", SlidingLog(10, 1.0), arrivals3)
    play("滑动窗口计数", SlidingCounter(10, 1.0), arrivals3)
    play("令牌桶 rate=10/s burst=10", TokenBucket(10, 10), arrivals3)

    print("\n" + "=" * 96)
    print("结论：")
    print("  · 固定窗口在边界处能放过 2 倍限额（陷阱一）——这是它最著名的缺陷。")
    print("  · 滑动窗口日志精确，但每个通过的请求都要存一个时间戳（内存随 QPS 线性增长）。")
    print("  · 滑动窗口计数用两个桶加权近似，内存恒定，代价是边界附近略有误差。")
    print("  · 令牌桶允许『攒额度的突发』（陷阱二）、长期速率又被 rate 卡住——")
    print("    这正是它适合放在 API 网关的原因：允许正常突发，不允许持续超额。")


if __name__ == "__main__":
    main()
