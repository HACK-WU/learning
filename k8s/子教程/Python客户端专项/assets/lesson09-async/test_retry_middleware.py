"""重试中间件测试

分两组：
  A. 纯逻辑单测（不碰集群）：分类、Retry-After 解析、budget
  B. 放大实测（注入故障）：验证 429 分支、预算对放大的抑制

⚠️ 诚实标注：429 分支靠**注入**验证（本机打不出真 429，见课 9 番外）。
   Retry-After 的 HTTP-date 分支同样为注入验证。
"""
import asyncio
import datetime
import sys
from email.utils import format_datetime

from retry_middleware import (
    ApiException, RetryPolicy, RetryStats, _Budget, classify,
    equal_jitter, gather_with_retry, parse_retry_after, retry_k8s,
)

PASS = FAIL = 0


def check(label, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ✓ {label} {detail}")
    else:
        FAIL += 1
        print(f"  ✗ {label} {detail}")


# ==========================================================================
# A. 纯逻辑单测
# ==========================================================================

def t_classify():
    print("=== A1. 错误分类 ===")
    check("409 -> retryable", classify(ApiException(409)) == "retryable")
    check("429 -> retryable", classify(ApiException(429)) == "retryable")
    check("500 -> retryable", classify(ApiException(500)) == "retryable")
    check("503 -> retryable", classify(ApiException(503)) == "retryable")
    check("404 -> fatal", classify(ApiException(404)) == "fatal")
    check("403 -> fatal", classify(ApiException(403)) == "fatal")
    check("401 -> fatal", classify(ApiException(401)) == "fatal")
    check("422 -> fatal", classify(ApiException(422)) == "fatal")
    check("网络异常 -> unknown", classify(ConnectionError("x")) == "unknown")


def t_retry_after():
    print()
    print("=== A2. Retry-After 解析 ===")

    def mk(v):
        e = ApiException(429, "Too Many Requests")
        e.headers = {"Retry-After": v} if v is not None else {}
        return e

    check("整数秒 '5'", parse_retry_after(mk("5")) == 5.0)
    check("浮点 '0.5'", parse_retry_after(mk("0.5")) == 0.5)
    check("负数 '-1' 归零", parse_retry_after(mk("-1")) == 0.0)
    check("无 header -> None", parse_retry_after(mk(None)) is None)

    # 大小写不敏感
    e = ApiException(429)
    e.headers = {"retry-after": "7"}
    check("小写头名 'retry-after'", parse_retry_after(e) == 7.0)

    # HTTP-date 形式（注入验证）
    future = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=10)
    e2 = ApiException(429)
    e2.headers = {"Retry-After": format_datetime(future)}
    v = parse_retry_after(e2)
    check("HTTP-date 近似 10s", v is not None and 8.0 <= v <= 12.0, f"got={v:.2f}")

    # 过去时间 -> 0
    past = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=30)
    e3 = ApiException(429)
    e3.headers = {"Retry-After": format_datetime(past)}
    check("过去的 HTTP-date -> 0", parse_retry_after(e3) == 0.0)

    # 垃圾值 -> None
    e4 = ApiException(429)
    e4.headers = {"Retry-After": "not-a-date"}
    check("非法值 -> None", parse_retry_after(e4) is None)


def t_jitter():
    print()
    print("=== A3. equal jitter 范围 ===")
    vals = [equal_jitter(0.05, 2.0, 2) for _ in range(2000)]
    lo, hi = min(vals), max(vals)
    # v = 0.05*4 = 0.2；equal jitter ∈ [v/2, v] = [0.1, 0.2]
    check("下界 >= v/2", lo >= 0.1 - 1e-9, f"min={lo:.4f}")
    check("上界 <= v", hi <= 0.2 + 1e-9, f"max={hi:.4f}")
    check("有分散（非恒定）", hi - lo > 0.05, f"跨度={hi-lo:.4f}")

    vals0 = [equal_jitter(0.05, 2.0, 0) for _ in range(1000)]
    check("attempt=0 范围 [0.025,0.05]",
          min(vals0) >= 0.025 - 1e-9 and max(vals0) <= 0.05 + 1e-9)

    # cap 生效
    big = [equal_jitter(0.05, 2.0, 20) for _ in range(500)]
    check("cap 封顶 2.0", max(big) <= 2.0 + 1e-9, f"max={max(big):.3f}")


async def t_fatal_no_retry():
    print()
    print("=== A4. fatal 立即放弃（不重试）===")
    calls = {"n": 0}

    async def fn():
        calls["n"] += 1
        raise ApiException(404, "Not Found")

    st = RetryStats()
    try:
        await retry_k8s(fn, policy=RetryPolicy(max_attempts=5), stats=st)
        check("应抛异常", False)
    except ApiException as e:
        check("抛出 404", e.status == 404)
        check("只调用 1 次（未重试）", calls["n"] == 1, f"实际 {calls['n']}")
        check("计入 fatal", st.class_fatal == 1)


async def t_raise_not_silent():
    print()
    print("=== A5. 放弃时 raise，不静默返回 ===")

    async def fn():
        raise ApiException(503)

    st = RetryStats()
    try:
        r = await retry_k8s(fn, policy=RetryPolicy(max_attempts=3), stats=st)
        check("应抛异常而非返回", False, f"却返回了 {r!r}")
    except ApiException:
        check("确实 raise", True)
        check("attempts == 3", st.attempts == 3, f"实际 {st.attempts}")


# ==========================================================================
# B. 注入式放大实测
# ==========================================================================

class Flaky:
    """注入故障的假 apiserver"""

    def __init__(self, fail_rate=1.0, status=429, retry_after=None):
        self.calls = 0
        self.fail_rate = fail_rate
        self.status = status
        self.retry_after = retry_after

    async def __call__(self):
        self.calls += 1
        if self.fail_rate >= 1.0 or (self.fail_rate > 0 and self.calls == 1):
            e = ApiException(self.status, "injected")
            if self.retry_after is not None:
                e.headers = {"Retry-After": str(self.retry_after)}
            raise e
        return "ok"


async def t_429_uses_retry_after():
    print()
    print("=== B1. 429 采纳 Retry-After ===")
    srv = Flaky(fail_rate=1.0, status=429, retry_after=0.05)
    st = RetryStats()
    try:
        await retry_k8s(srv, policy=RetryPolicy(max_attempts=3), stats=st)
    except ApiException:
        pass
    check("采纳 Retry-After 次数 == 2", st.used_retry_after == 2,
          f"实际 {st.used_retry_after}")
    check("总等待约 0.1s", abs(st.slept_seconds - 0.1) < 0.02,
          f"{st.slept_seconds:.4f}s")

    # 关掉 respect_retry_after 后应退回 jitter
    srv2 = Flaky(fail_rate=1.0, status=429, retry_after=0.05)
    st2 = RetryStats()
    try:
        await retry_k8s(srv2, policy=RetryPolicy(
            max_attempts=3, respect_retry_after=False, base_delay=0.05), stats=st2)
    except ApiException:
        pass
    check("关闭后不采纳 Retry-After", st2.used_retry_after == 0)

    # 修正断言（2026-09-29）：
    # 原断言「等待 < 0.1s」是错的。max_attempts=3 时有 2 次等待：
    #   attempt0: equal_jitter(0.05, 2.0, 0) ∈ [0.025, 0.05]
    #   attempt1: equal_jitter(0.05, 2.0, 1) ∈ [0.050, 0.100]
    # 合计理论范围 [0.075, 0.150]，本就可能 > 0.1，故原断言会偶发失败。
    # 正确判据：① 落在理论范围 ② 多次运行有随机波动（不是 Retry-After 的固定值）
    check("jitter 等待落在理论范围 [0.075,0.15]",
          0.075 - 1e-6 <= st2.slept_seconds <= 0.150 + 1e-6,
          f"{st2.slept_seconds:.4f}s")

    samples = []
    for _ in range(12):
        s = Flaky(fail_rate=1.0, status=429, retry_after=0.05)
        stx = RetryStats()
        try:
            await retry_k8s(s, policy=RetryPolicy(
                max_attempts=3, respect_retry_after=False,
                base_delay=0.05), stats=stx)
        except ApiException:
            pass
        samples.append(stx.slept_seconds)
    spread = max(samples) - min(samples)
    check("jitter 有随机波动（非固定 0.1）", spread > 0.005,
          f"跨度 {spread:.4f}s, 样本 {min(samples):.4f}~{max(samples):.4f}")


async def t_retry_after_cap():
    print()
    print("=== B2. Retry-After 上限保护 ===")
    srv = Flaky(fail_rate=1.0, status=429, retry_after=999)
    st = RetryStats()
    try:
        await retry_k8s(srv, policy=RetryPolicy(
            max_attempts=2, retry_after_cap=0.03), stats=st)
    except ApiException:
        pass
    check("被 cap 截断到 0.03", abs(st.slept_seconds - 0.03) < 0.01,
          f"{st.slept_seconds:.4f}s")


async def t_budget():
    print()
    print("=== B3. 重试预算抑制放大 ===")

    async def run(ratio, n=50, attempts=6):
        budget = _Budget(ratio=ratio) if ratio > 0 else None
        st = RetryStats()
        coros = []
        for _ in range(n):
            srv = Flaky(fail_rate=1.0, status=503)
            coros.append(retry_k8s(
                srv, policy=RetryPolicy(max_attempts=attempts),
                stats=st, budget=budget))
        await asyncio.gather(*coros, return_exceptions=True)
        return st.attempts / n, st

    amp_no, _ = await run(0)
    amp_b, st_b = await run(0.5)

    print(f"     无预算放大 {amp_no:.2f}x / 预算0.5 放大 {amp_b:.2f}x")
    check("无预算时接近满重试", amp_no >= 5.5, f"{amp_no:.2f}x")
    check("预算 0.5 显著更低", amp_b < amp_no * 0.75, f"{amp_b:.2f}x")
    check("预算耗尽被计数", st_b.budget_exhausted > 0,
          f"{st_b.budget_exhausted} 次")


async def t_concurrency_gate():
    print()
    print("=== B4. 并发闸门限制在飞数 ===")
    inflight = {"cur": 0, "peak": 0}

    async def fn():
        inflight["cur"] += 1
        inflight["peak"] = max(inflight["peak"], inflight["cur"])
        await asyncio.sleep(0.01)
        inflight["cur"] -= 1
        return "ok"

    sem = asyncio.Semaphore(5)
    calls = [(fn, (), {}) for _ in range(50)]
    ok, st = await gather_with_retry(calls, policy=RetryPolicy(
        max_attempts=1, max_concurrency=5))
    check("50 个全部完成", len(ok) == 50, f"{len(ok)}")
    check("峰值在飞 <= 5", inflight["peak"] <= 5, f"peak={inflight['peak']}")

    # 对照组：不加闸门
    inflight2 = {"cur": 0, "peak": 0}

    async def fn2():
        inflight2["cur"] += 1
        inflight2["peak"] = max(inflight2["peak"], inflight2["cur"])
        await asyncio.sleep(0.01)
        inflight2["cur"] -= 1
        return "ok"

    calls2 = [(fn2, (), {}) for _ in range(50)]
    await gather_with_retry(calls2, policy=RetryPolicy(max_attempts=1))
    check("无闸门时峰值远高", inflight2["peak"] > inflight["peak"],
          f"{inflight2['peak']} > {inflight['peak']}")


async def t_partial_success():
    print()
    print("=== B5. 批量部分失败不中断 ===")
    ok_calls = []

    def make_ok():
        async def fn():
            ok_calls.append(1)
            return "ok"
        return fn

    calls = []
    for i in range(10):
        if i % 2 == 0:
            calls.append((make_ok(), (), {}))
        else:
            calls.append((Flaky(fail_rate=1.0, status=500), (), {}))

    ok, st = await gather_with_retry(calls, policy=RetryPolicy(max_attempts=2))
    check("成功 5 个", len(ok) == 5, f"{len(ok)}")
    check("失败计入 retryable", st.class_retryable > 0)


async def main():
    t_classify()
    t_retry_after()
    t_jitter()
    await t_fatal_no_retry()
    await t_raise_not_silent()
    print()
    print("--- 注入式 ---")
    await t_429_uses_retry_after()
    await t_retry_after_cap()
    await t_budget()
    await t_concurrency_gate()
    await t_partial_success()

    print()
    print(f"===== 通过 {PASS} / 失败 {FAIL} =====")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
