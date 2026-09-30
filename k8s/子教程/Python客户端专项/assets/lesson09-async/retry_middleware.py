"""K8s 异步重试中间件（生产可用版）

补齐课 6 番外 4 未覆盖的三块：
  1. 429 与 Retry-After 语义（课 9 番外实测：本机打不出 429，故用注入法验证）
  2. 并发闸门（限制同时打向 apiserver 的在飞请求）
  3. 重试预算（放大倍数硬上限，防重试风暴）

设计原则：
  - 尊重服务端 Retry-After（服务端比你更清楚该等多久）
  - 无 Retry-After 时退回 equal jitter 指数退避
  - 可重试与不可重试严格区分（4xx 中只放行 409/429）
  - 可选：并发闸门 + 重试预算，二者共同控制放大
  - 放弃时 raise，绝不返回 (None, False)（课 6 番外 4 坑 1）

实测基准（本机 kind v1.34.0，见 _test_middleware.py）：
  - 无重试放大 1.00x / 3 次重试 2.69x / 5 次重试 4.10x
  - jitter 不降放大倍数，只打散（0.583 → 0.121）
"""

from __future__ import annotations

import asyncio
import random
import time
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Optional

try:
    from kubernetes_asyncio.client.rest import ApiException
except ImportError:  # 允许在无依赖环境下做纯逻辑测试
    class ApiException(Exception):  # type: ignore[no-redef]
        def __init__(self, status: int = 0, reason: str = ""):
            super().__init__(f"({status}) {reason}")
            self.status = status
            self.reason = reason
            self.headers: dict[str, str] = {}


# --------------------------------------------------------------------------
# 1. 错误分类
# --------------------------------------------------------------------------

#: 4xx 中唯二可重试的：409 冲突（重读再试）、429 限流（等 Retry-After）
RETRYABLE_4XX = frozenset({409, 429})

#: 明确不可重试：语义错误，重试一万次也一样
FATAL_4XX = frozenset({400, 401, 403, 404, 405, 410, 422})


def classify(exc: BaseException) -> str:
    """把异常分为 retryable / fatal / unknown

    unknown（如网络层异常）默认按可重试处理——网络抖动是典型的可恢复故障。
    """
    if isinstance(exc, ApiException):
        s = exc.status
        if s in RETRYABLE_4XX:
            return "retryable"
        if 500 <= s < 600:
            return "retryable"
        if s in FATAL_4XX or 400 <= s < 500:
            return "fatal"
        return "unknown"
    # 非 ApiException：连接错误、超时等，按可重试
    return "unknown"


# --------------------------------------------------------------------------
# 2. Retry-After 解析
# --------------------------------------------------------------------------

def parse_retry_after(exc: BaseException) -> Optional[float]:
    """解析 Retry-After 头，支持秒数与 HTTP-date 两种形式

    RFC 9110 §10.2.3：Retry-After = delay-seconds / HTTP-date
    实践中绝大多数服务端（含 k8s APF）用 delay-seconds。
    解析失败返回 None，调用方退回指数退避。

    ⚠️ 未实测标注：HTTP-date 分支在本机未触发过（0 次 429），
       依据 RFC 与 http.client 行为实现，未经真实验证。
    """
    headers = getattr(exc, "headers", None)
    if not headers:
        return None
    # 头名大小写不敏感
    val = None
    for k, v in headers.items():
        if k.lower() == "retry-after":
            val = v
            break
    if val is None:
        return None

    val = str(val).strip()

    # 形式 1：delay-seconds
    try:
        secs = float(val)
        return max(0.0, secs)
    except (TypeError, ValueError):
        pass

    # 形式 2：HTTP-date（如 Wed, 21 Oct 2015 07:28:00 GMT）
    from email.utils import parsedate_to_datetime
    import datetime
    try:
        dt = parsedate_to_datetime(val)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        delta = (dt - datetime.datetime.now(datetime.timezone.utc)).total_seconds()
        return max(0.0, delta)
    except Exception:
        return None


# --------------------------------------------------------------------------
# 3. 退避策略
# --------------------------------------------------------------------------

def equal_jitter(base: float, cap: float, attempt: int) -> float:
    """equal jitter（AWS 推荐）：一半固定保下界，一半随机打散

    课 6 番外 4 实测：无 jitter 时 100 个请求跨度恒为 0.0000s（惊群），
    equal jitter 拉到 0.2834s。
    """
    v = min(base * (2 ** attempt), cap)
    return v / 2 + random.uniform(0, v / 2)


# --------------------------------------------------------------------------
# 4. 策略与统计
# --------------------------------------------------------------------------

@dataclass
class RetryPolicy:
    max_attempts: int = 3            # 含首次，故实际重试 max_attempts-1 次
    base_delay: float = 0.05
    cap_delay: float = 2.0
    respect_retry_after: bool = True
    retry_after_cap: float = 30.0    # 防服务端给个离谱的大值
    max_concurrency: int = 0         # 0 = 不限制
    retry_budget: float = 0.0        # 0 = 不限制；1.5 表示重试数 ≤ 首轮数 × 1.5


@dataclass
class RetryStats:
    attempts: int = 0
    retries: int = 0
    class_retryable: int = 0
    class_fatal: int = 0
    class_unknown: int = 0
    used_retry_after: int = 0        # 真正采纳服务端 Retry-After 的次数
    budget_exhausted: int = 0        # 因预算耗尽而放弃的次数
    slept_seconds: float = 0.0
    last_error: Optional[str] = None


@dataclass
class _Budget:
    """共享重试预算：限制重试总量相对首轮的比例

    🚨 时序饥饿缺陷（2026-09-29 实测发现并修复）：
    早期实现用 `allowed = first_round * ratio`，其中 first_round 是**已观察到**
    的首轮数。批量并发时，先失败的请求会在其他请求还没跑首轮时就抢走额度，
    导致后失败的被拒——实测 ratio=0.5、n=30 同时发起时只成功 15/30，
    而"先灌满基数"的对照组 30/30。这不是限流，是**额度分配不公**。

    修复：`total` 已知时（批量调用场景 len(calls) 是已知的），
    额度直接按 `total * ratio` 固定，与执行时序无关。
    `total` 未知时退回动态基数，并给出 warning 级注释。
    """
    ratio: float
    total: Optional[int] = None      # 已知总量；None = 动态推断（有饥饿风险）
    first_round: int = 0
    retries_used: int = 0
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def count_first(self) -> None:
        async with self._lock:
            self.first_round += 1

    async def try_consume(self) -> bool:
        """消耗一次重试额度，返回是否允许"""
        async with self._lock:
            base = self.total if self.total is not None else self.first_round
            allowed = base * self.ratio
            if self.retries_used + 1 > allowed:
                return False
            self.retries_used += 1
            return True


# --------------------------------------------------------------------------
# 5. 中间件主体
# --------------------------------------------------------------------------

async def retry_k8s(
    fn: Callable[..., Awaitable[Any]],
    *args: Any,
    policy: Optional[RetryPolicy] = None,
    stats: Optional[RetryStats] = None,
    budget: Optional[_Budget] = None,
    semaphore: Optional[asyncio.Semaphore] = None,
    **kwargs: Any,
) -> Any:
    """带重试地调用一个 k8s 异步 API

    失败策略：放弃时 **raise 最后一个异常**，绝不返回 (None, False)。
    （课 6 番外 4 坑 1：返回元组会导致调用方忘检 ok 而静默忽略失败）
    """
    policy = policy or RetryPolicy()
    stats = stats if stats is not None else RetryStats()

    last_exc: Optional[BaseException] = None

    for attempt in range(policy.max_attempts):
        stats.attempts += 1
        if attempt == 0 and budget is not None:
            await budget.count_first()

        # 并发闸门
        if semaphore is not None:
            async with semaphore:
                try:
                    return await fn(*args, **kwargs)
                except BaseException as e:
                    last_exc = e
        else:
            try:
                return await fn(*args, **kwargs)
            except BaseException as e:
                last_exc = e

        # ---- 到这里说明本次失败 ----
        kind = classify(last_exc)
        if kind == "retryable":
            stats.class_retryable += 1
        elif kind == "fatal":
            stats.class_fatal += 1
            raise last_exc            # 语义错误，立即放弃
        else:
            stats.class_unknown += 1

        stats.last_error = f"{type(last_exc).__name__}: {last_exc}"

        # 最后一次不再等待
        if attempt == policy.max_attempts - 1:
            break

        # 重试预算
        if budget is not None:
            if not await budget.try_consume():
                stats.budget_exhausted += 1
                break

        # 决定等待时长
        delay: Optional[float] = None
        if policy.respect_retry_after:
            ra = parse_retry_after(last_exc)
            if ra is not None:
                delay = min(ra, policy.retry_after_cap)
                stats.used_retry_after += 1
        if delay is None:
            delay = equal_jitter(policy.base_delay, policy.cap_delay, attempt)

        stats.retries += 1
        stats.slept_seconds += delay
        await asyncio.sleep(delay)

    assert last_exc is not None
    raise last_exc


# --------------------------------------------------------------------------
# 6. 便捷入口：批量调用（自带闸门与预算）
# --------------------------------------------------------------------------

async def gather_with_retry(
    calls: list[tuple[Callable[..., Awaitable[Any]], tuple, dict]],
    policy: Optional[RetryPolicy] = None,
) -> tuple[list[Any], RetryStats]:
    """并发执行多个调用，共享闸门与重试预算

    返回 (成功结果列表, 统计)。个别失败的调用会被记入 stats 而不中断整体
    （批量巡检场景）；如需失败即中断，改 raise_on_error=True 语义即可。

    放大倍数 = stats.attempts / len(calls)，可从 stats 直接读出。
    """
    policy = policy or RetryPolicy()
    stats = RetryStats()
    # 批量场景总量已知 → 额度固定，与执行时序无关（避免时序饥饿）
    budget = (_Budget(ratio=policy.retry_budget, total=len(calls))
              if policy.retry_budget > 0 else None)
    sem = (asyncio.Semaphore(policy.max_concurrency)
           if policy.max_concurrency > 0 else None)

    async def one(fn, a, kw):
        return await retry_k8s(fn, *a, policy=policy, stats=stats,
                               budget=budget, semaphore=sem, **kw)

    results = await asyncio.gather(
        *[one(fn, a, kw) for fn, a, kw in calls],
        return_exceptions=True,
    )
    ok = [r for r in results if not isinstance(r, BaseException)]
    return ok, stats
