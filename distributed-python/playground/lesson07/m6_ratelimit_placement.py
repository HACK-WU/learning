"""M6：限流该配在哪一层 —— 确定性时间轴模拟，只数"下游被打了几次"。

为什么用确定性时间轴而不是起线程真打：这里要回答的是一个算术问题
（N 个实例各自合规，合计是多少），真实网络抖动只会让数字更难读。

设定：
  上游 6 个实例，每个实例"自我感觉"配了 5 QPS
  下游对外承诺的容量是 10 QPS
  时间轴 3 秒

三种方案：
  ① 只在调用方限流（每实例 5 QPS）
  ② 只在被调方限流（服务端统一 10 QPS）
  ③ 两边都不限，只靠超时兜底
"""
DURATION = 3.0
INSTANCES = 6
PER_INSTANCE_QPS = 5
DOWNSTREAM_QUOTA = 10          # 下游承诺的容量（QPS）
UNLIMITED_QPS = 100            # 方案③：不限流时上游能打多快（含重试）


class TokenBucket:
    def __init__(self, rate, burst=None):
        self.rate = rate
        self.burst = burst if burst is not None else rate
        self.tokens = self.burst
        self.last = 0.0

    def allow(self, now):
        self.tokens = min(self.burst, self.tokens + (now - self.last) * self.rate)
        self.last = now
        if self.tokens >= 1:
            self.tokens -= 1
            return True
        return False


def arrivals(rate, n_streams=1):
    """按 rate 匀速生成到达时刻（每个流一条独立均匀流）。"""
    times = []
    step = 1.0 / rate
    for s in range(n_streams):
        offset = s * step / n_streams
        t = offset
        while t < DURATION:
            times.append(t)
            t += step
    return sorted(times)


def plan_client_limit():
    """① 每个实例各自限流 5 QPS —— 每个都合规，合计不限。"""
    per_instance = []
    for _ in range(INSTANCES):
        b = TokenBucket(PER_INSTANCE_QPS)
        passed = [t for t in arrivals(PER_INSTANCE_QPS) if b.allow(t)]
        per_instance.append(len(passed))
    # 每个实例的真实意愿就是 5 QPS；各自限流后依然全放行
    willing = INSTANCES * PER_INSTANCE_QPS * DURATION
    sent = sum(per_instance)
    return sent, willing


def plan_server_limit():
    """② 被调方（下游入口）统一限流 10 QPS。上游意愿 30 QPS 全打过来，入口只放 10 QPS。"""
    offered = arrivals(INSTANCES * PER_INSTANCE_QPS)
    b = TokenBucket(DOWNSTREAM_QUOTA, burst=1)   # burst=1 —— 严格配额，不攒突发
    passed = [t for t in offered if b.allow(t)]
    return len(passed), len(offered)


def plan_no_limit():
    """③ 谁都不限 —— 上游以 100 QPS 的意愿直接压过来。"""
    offered = arrivals(UNLIMITED_QPS)
    return len(offered), len(offered)


def main():
    print("=" * 88)
    print(f"上游 {INSTANCES} 个实例 × 每个 {PER_INSTANCE_QPS} QPS"
          f" = 合计意愿 {INSTANCES * PER_INSTANCE_QPS} QPS")
    print(f"下游对外承诺容量 {DOWNSTREAM_QUOTA} QPS ｜ 时间轴 {DURATION:.0f}s")
    print(f"理论：3 秒内下游最多该被打 {int(DOWNSTREAM_QUOTA * DURATION)} 次")

    rows = []
    for name, fn, note in [
        ("① 只在调用方限流", plan_client_limit, "每实例 5 QPS，各自都合规"),
        ("② 只在被调方限流", plan_server_limit, "入口统一 10 QPS（burst=1）"),
        ("③ 都不限，只超时", plan_no_limit, "没人为总量负责"),
    ]:
        hit, offered = fn()
        qps = hit / DURATION
        rows.append((name, note, offered, hit, qps, qps / DOWNSTREAM_QUOTA))

    print("\n" + "-" * 88)
    print(f"{'方案':<18}{'说明':<22}{'上游发起':>10}{'下游实收':>10}"
          f"{'实收 QPS':>10}{'超容量':>10}")
    print("-" * 88)
    for name, note, offered, hit, qps, ratio in rows:
        flag = "  ← 超了" if ratio > 1.0 else ""
        print(f"{name:<18}{note:<22}{offered:>10}{hit:>10}"
              f"{qps:>10.1f}{ratio:>9.2f}×{flag}")
    print("-" * 88)

    print("\n结论：")
    print("  · ① 每个实例都严格守住了自己的 5 QPS，但合计 30 QPS —— 下游被超 3 倍。")
    print("    『每个都合规』不等于『整体合规』，这是分布式限流最常见的误配。")
    print("  · ② 只有在下游入口（或被保护的资源旁）限总量，才能锁住真实速率。")
    print("  · ③ 不限流时，超时和重试只会让下游更忙——限流是唯一能主动减少请求的手段。")

    print("\n补充：如果调用方之间无法协调，那就必须让被调方持有唯一的计数器")
    print("      （服务端限流 / 集中式限流器 / 网关层限流），而不是靠约定大家都守规矩。")


if __name__ == "__main__":
    main()
