# 课 10：重试中间件工程化（429 / Retry-After / 放大控制）

> 前置：[课 9 番外：异步三个未实测项](lesson-09-async-异步三个未实测项.md)、[课 6 番外 4：重试与指数退避](lesson-06-async4-重试与指数退避.md)、[课 5：错误处理与健壮性](lesson-05-错误处理与健壮性.md)
> 代码：[retry_middleware.py](../assets/lesson09-async/retry_middleware.py)、[test_retry_middleware.py](../assets/lesson09-async/test_retry_middleware.py)
> 环境：k8s v1.34.0（`kind-k8s-c1`）；`kubernetes-asyncio` 36.1.0；Python 3.12.3
> 测试：**48 项断言全通过**（主套件 41 + 修复验证 7，连跑 3 次稳定），全部为注入式故障验证

---

## 引子：理论会了，为什么还要一个中间件？

课 6 番外 4 已经把重试讲透了：指数退避、equal jitter、惊群、队头阻塞。课 9 番外又实测了重试风暴的放大倍数。

那还缺什么？**缺一个能直接拿去用的东西。**

课 6 番外 4 的 `retry_async` 是个教学版函数，它没处理三件生产必遇的事：

1. **429 与 `Retry-After`**——服务端明确告诉你"等 N 秒"，你却在用自己的退避公式瞎猜
2. **并发闸门**——1000 个对象同时调谐，重试时全部一起冲向 apiserver
3. **放大硬上限**——重试次数只能限制"单个调用"，限制不了"整体放大倍数"

更关键的是，课 6 番外 4 踩过一个坑（坑 1）：`retry_async` 返回 `(None, False)` 导致调用方忘记检查、失败被静默吞掉。这类"程序不报错但功能已失效"的缺陷，靠每次手写是防不住的，得**固化到中间件里**。

这篇就做这件事：一个生产可用的异步重试中间件，以及**我在实现过程中抓到的一个真缺陷**。

---

## 第一幕：设计目标

中间件要同时满足五条，缺一不可：

| 目标 | 做法 | 依据 |
|------|------|------|
| 尊重服务端 | 优先采纳 `Retry-After` | 服务端比你清楚该等多久 |
| 不瞎重试 | 严格区分 fatal / retryable | 404 重试一万次也是 404 |
| 不惊群 | 无 `Retry-After` 时退回 equal jitter | 课 6 番外 4 实测跨度 0.0000s → 0.2834s |
| 不冲垮 | 并发闸门限在飞数 | 课 9 番外：并发放大可达 4.10x |
| 不失控 | 重试预算限放大倍数 | 课 9 番外实测 |
| **不静默** | 放弃时 `raise`，绝不返回 `(None, False)` | 课 6 番外 4 坑 1 |

最后一条是底线。课 6 番外 4 用血的教训换来的：返回元组 → 调用方忘检 → `requeued=0` 而程序毫无反应。

---

## 第二幕：错误分类——哪些该重试

### 2.1 4xx 里只有两个可重试

```python
RETRYABLE_4XX = frozenset({409, 429})
FATAL_4XX = frozenset({400, 401, 403, 404, 405, 410, 422})
```

| 状态码 | 分类 | 理由 |
|--------|------|------|
| 409 Conflict | retryable | 版本冲突，**重读再试**即可（课 3 patch 语义） |
| 429 Too Many Requests | retryable | 限流，等 `Retry-After` |
| 5xx | retryable | 服务端暂时不可用 |
| 400/401/403/404/405/410/422 | **fatal** | 语义错误，重试无意义 |
| 非 `ApiException`（超时/连接错误） | unknown → 按可重试 | 网络抖动是典型可恢复故障 |

实测（A1）：

```text
✓ 409 -> retryable    ✓ 429 -> retryable    ✓ 500 -> retryable
✓ 404 -> fatal        ✓ 403 -> fatal        ✓ 422 -> fatal
✓ 网络异常 -> unknown
```

### 2.2 fatal 必须立即放弃

```text
✓ 抛出 404
✓ 只调用 1 次（未重试）    实际 1
✓ 计入 fatal
```

**这是很多手写重试最容易错的地方**：把所有异常一律重试，结果 403 权限不足也重试 5 次，白白浪费 5 次请求还拖慢报错。

### 2.3 放弃时 raise，绝不静默

```text
✓ 确实 raise
✓ attempts == 3
```

对比课 6 番外 4 的缺陷版本：

```python
_, ok = await retry_async(...)     # ❌ 忘检 ok，失败被吞
```

中间件版本：

```python
try:
    r = await retry_k8s(api.read_namespaced_pod, name, ns)
except ApiException as e:
    ...                             # 必须处理，无法忽略
```

---

## 第三幕：`Retry-After` —— 服务端说了算

### 3.1 解析要支持两种形式

RFC 9110 §10.2.3 规定 `Retry-After` 可以是**秒数**或 **HTTP-date**：

```python
Retry-After: 5                              # delay-seconds
Retry-After: Wed, 21 Oct 2015 07:28:00 GMT  # HTTP-date
```

实测覆盖（A2）：

```text
✓ 整数秒 '5'              ✓ 浮点 '0.5'
✓ 负数 '-1' 归零          ✓ 无 header -> None
✓ 小写头名 'retry-after'   ✓ HTTP-date 近似 10s  got=9.43
✓ 过去的 HTTP-date -> 0    ✓ 非法值 -> None
```

三个容易漏的点：

- **头名大小写不敏感**（`retry-after` 与 `Retry-After` 都要认）
- **负数要归零**（否则 `asyncio.sleep(-1)` 直接 `ValueError`）
- **解析失败返回 `None`**，退回 jitter，而不是抛异常

> ⚠️ **未实测标注**：HTTP-date 分支在本机**未触发过**（0 次真 429），依据 RFC 与 `email.utils` 行为实现，属**注入式验证**。生产使用前建议在你的集群确认服务端实际用哪种形式。

### 3.2 采纳 `Retry-After` 优于自己算

实测（B1）：服务端给 `Retry-After: 0.05`，两次重试后

```text
✓ 采纳 Retry-After 次数 == 2
✓ 总等待约 0.1s           0.1000s
```

关掉后退回 jitter：

```text
✓ 关闭后不采纳 Retry-After
✓ jitter 有随机波动（非固定 0.1）  跨度 0.0183s
```

### 3.3 必须给 `Retry-After` 加上限

服务端可能给你一个离谱的大值（甚至写错单位）。中间件用 `retry_after_cap` 截断：

```text
✓ 被 cap 截断到 0.03      0.0300s   （服务端给 999 秒）
```

缺省 `retry_after_cap=30.0`。没有这个保护，一个配置错误的服务端能让你的控制器睡死过去。

---

## 第四幕：两个放大控制器

课 9 番外实测：p=0.9 时 3 次重试放大 **2.69x**、5 次放大 **4.10x**。`max_attempts` 只能限制单个调用，限制不了整体。所以中间件提供两个额外的闸：

### 4.1 并发闸门（限在飞数）

```python
asyncio.Semaphore(max_concurrency)
```

实测（B4）：

```text
✓ 50 个全部完成
✓ 峰值在飞 <= 5          peak=5
✓ 无闸门时峰值远高        50 > 5
```

**对照很直观**：不加闸门时 50 个请求同时在飞；加 `max_concurrency=5` 后峰值严格 5。

### 4.2 重试预算（限放大倍数）

`retry_budget=0.5` 表示"重试次数 ≤ 首轮数 × 0.5"，即放大上限 1.5x。

实测（`_verify_budget.py` V2，`max_attempts=4`、每个调用失败 1 次）：

```text
    ratio     成功      放大     重试     耗尽
      0.0   40/40   2.00x     40      0
     0.25   10/40   1.25x     10     30
      0.5   20/40   1.50x     20     20
      1.0   40/40   2.00x     40      0
```

放大被**精确**控制在 `1 + ratio`。

---

## 第五幕：🚨 我在预算实现里抓到的一个真缺陷

这一节是本篇最值钱的部分。

### 5.1 疑点：数字太整齐

B3 跑出来 `ratio=0.5` 时放大恰好 **1.50x**、预算耗尽恰好 **50 次**（等于全部调用数）。

按铁律，**数字太整齐先怀疑测量方法/实现**。50 次耗尽意味着**所有重试都被拒了**——那预算就不是"限制放大"，而是"干脆不许重试"，这是缺陷不是特性。

### 5.2 验证：时序饥饿

写了个对照实验（`_verify_budget.py` V3）：

```text
全部同时发起: 成功 15/30, first_round=30, retries_used=15
理论允许重试 = 15
实际重试     = 15

对照：先完成首轮计数再重试（预热）
预热后: 成功 30/30, retries_used=30
→ 差异说明：时序饥饿确实存在
```

**同样的 `ratio=0.5`、同样的 30 个调用**，同时发起只成功 15/30，预热组 30/30。

### 5.3 根因

原实现：

```python
async def try_consume(self) -> bool:
    async with self._lock:
        allowed = self.first_round * self.ratio   # ← first_round 是"已观察到"的
        ...
```

`first_round` 是**已经跑过首轮的调用数**。批量并发时，先失败的请求在其他请求还没跑首轮时就抢走额度——那时 `first_round` 还很小，`allowed` 自然小，早期重试被拒；等后面的请求失败时，额度已被抢光。

**这不是限流，是额度分配不公**。而且它有隐蔽性：单独调用没问题，一上并发就现形。

### 5.4 修复

批量场景里**调用总数是已知的**（`len(calls)`），额度应该据此固定：

```python
@dataclass
class _Budget:
    ratio: float
    total: Optional[int] = None      # 已知总量
    ...

    async def try_consume(self) -> bool:
        async with self._lock:
            base = self.total if self.total is not None else self.first_round
            allowed = base * self.ratio
            ...
```

`gather_with_retry` 自动传入 `total=len(calls)`。

### 5.5 修复验证

```text
✓ 额度用满              used=15 / allowed=15
✓ 成功率 = 额度/总数     15
✓ ratio=1.0 全部成功     30/30
✓ ratio=0.5 成功约一半   15/30, 放大 1.50x
```

同时回归确认没破坏原有能力：

```text
✓ 无预算全成功          20/20
✓ 放大 2.00x           2.00x
✓ 404 仍只调 1 次       1
```

### 5.6 教训

这个缺陷和课 9 番外的三次测法错误**同型**：都是"看起来在工作，实际在另一个层面失效"。

区别是这次**不是测法错，是实现错**——但抓到它的手段是一样的：**对太整齐的数字保持怀疑**。放大恰好 1.50x、耗尽恰好 50 次，这种"完美"本身就是警报。

---

## 第六幕：🚨 又一个断言写错（第 9 次测法错误）

修复后连跑测试，B1 偶发失败：

```text
✗ 改用 jitter（等待 < 0.1s）   0.1096s
```

**我的断言写错了**，不是代码错了。

`max_attempts=3` 时有两次等待：

```text
attempt0: equal_jitter(0.05, 2.0, 0) ∈ [0.025, 0.05]
attempt1: equal_jitter(0.05, 2.0, 1) ∈ [0.050, 0.100]
合计理论范围 [0.075, 0.150]
```

**0.1096s 完全落在理论范围内**，我却断言它必须 < 0.1s。错在：我想验证"用的是 jitter 而不是 `Retry-After` 的固定 0.1"，却用了个**绝对值比较**当判据——而 jitter 的和本就可能大于 0.1。

正确判据应该是**随机性**（jitter 每次不同，固定值每次相同）：

```python
samples = [多次运行的 slept_seconds]
spread = max(samples) - min(samples)
check("jitter 有随机波动（非固定 0.1）", spread > 0.005)
```

修正后连跑 3 次：**48/48 稳定通过**。

> 这是本系列第 9 次测法错误。模式已经很清晰：**断言的判据必须与要验证的性质一一对应**。要验证"随机"，就不能用"大小"来判。

---

## 速览

| 能力 | 做法 | 实测 |
|------|------|------|
| 错误分类 | 4xx 只放行 409/429，其余 fatal | A1 全通过 |
| fatal 立即放弃 | 不重试，直接 raise | 只调用 1 次 |
| 不静默失败 | 放弃时 `raise` | A5 |
| `Retry-After` 秒数 | 直接采纳 | `5 / 0.5 / -1→0` |
| `Retry-After` HTTP-date | `email.utils` 解析 | 近似 10s |
| 头名大小写 | 不敏感 | `retry-after` 生效 |
| 解析失败 | 返回 `None` 退回 jitter | 非法值 |
| 上限保护 | `retry_after_cap=30.0` | 999s → 0.03s |
| equal jitter | `v/2 + U(0, v/2)` | 范围与 cap 全过 |
| 并发闸门 | `Semaphore` | 峰值 5 vs 无闸门 50 |
| 重试预算 | `total × ratio` 固定额度 | 放大精确 1+ratio |
| **预算时序饥饿** | 🚨 用 `total` 而非 `first_round` | 15/30 → 与预热一致 |
| **断言判据错** | 🚨 验证随机性不能用大小比较 | 第 9 次测法错误 |

---

## 用法

### 单个调用

```python
from retry_middleware import RetryPolicy, RetryStats, retry_k8s

policy = RetryPolicy(
    max_attempts=3,
    base_delay=0.05,
    cap_delay=2.0,
    respect_retry_after=True,     # 429 优先听服务端的
    retry_after_cap=30.0,         # 但最多等 30 秒
)

stats = RetryStats()
try:
    pod = await retry_k8s(
        core.read_namespaced_pod, "my-pod", "default",
        policy=policy, stats=stats)
except ApiException as e:
    log.error("最终失败: %s", e)

print(f"放大 {stats.attempts}x, 等待 {stats.slept_seconds:.2f}s")
```

### 批量调用（推荐）

```python
from retry_middleware import RetryPolicy, gather_with_retry

calls = [
    (core.read_namespaced_pod, (f"pod-{i}", "default"), {})
    for i in range(200)
]

ok, stats = await gather_with_retry(calls, policy=RetryPolicy(
    max_attempts=4,
    max_concurrency=20,     # 最多 20 个在飞
    retry_budget=1.0,       # 放大上限 2.0x
))

print(f"成功 {len(ok)}/{len(calls)}, 放大 {stats.attempts/len(calls):.2f}x")
print(f"采纳 Retry-After {stats.used_retry_after} 次, "
      f"预算耗尽 {stats.budget_exhausted} 次")
```

### 参数怎么选

| 参数 | 建议 | 理由 |
|------|------|------|
| `max_attempts` | 3~4 | 课 9 番外：5 次放大 4.10x，收益递减 |
| `max_concurrency` | 10~50 | 按 apiserver 承受力；kind 可放宽 |
| `retry_budget` | 0.5~1.0 | 放大上限 1.5x~2.0x |
| `retry_after_cap` | 30.0 | 防服务端配置错误把你睡死 |
| `base_delay` | 0.05 | 首次重试很快，后续指数拉大 |

---

## 小测

1. 4xx 里哪些该重试？403 为什么不该？
2. 服务端返回 `Retry-After: 999`，中间件会怎么做？为什么必须这样？
3. 课 6 番外 4 的 `retry_async` 返回 `(None, False)` 有什么隐患？中间件怎么解决的？
4. 重试预算原实现有什么缺陷？表现是什么？根因是什么？
5. 为什么"放大恰好 1.50x、耗尽恰好 50 次"这种整齐数字值得怀疑？
6. 我想验证"用的是 jitter 而非固定 0.1"，用"等待 < 0.1s"做判据为什么错？正确判据是什么？
7. `max_attempts` 能不能替代 `retry_budget`？为什么？
8. 并发闸门和重试预算分别控制什么？只留一个够吗？

<details>
<summary>答案</summary>

1. 只有 **409（冲突，重读再试）** 和 **429（限流，等 Retry-After）**。403 是权限不足，属于语义错误——重试一万次也不会突然有权限，白白浪费请求还拖慢报错。
2. 会被 `retry_after_cap`（默认 30.0）截断到 30 秒。必须加这个保护，否则服务端一个配置错误（或单位写错）能让控制器睡死过去。
3. 调用方容易忘记检查 `ok`，失败被**静默吞掉**——程序不报错但功能已失效（课 6 番外 4 实测 `requeued=0`）。中间件改为放弃时直接 `raise`，调用方无法忽略。
4. **时序饥饿**。表现：同样 `ratio=0.5`、n=30，同时发起只成功 15/30，而"先灌满基数"的对照组 30/30。根因：`allowed = first_round * ratio` 用的是**已观察到**的首轮数，先失败的请求在其他请求还没跑首轮时就把额度抢光。修复：批量场景 `total` 已知，额度按 `total × ratio` 固定。
5. 因为这种"完美"恰恰说明**所有重试都被拒了**——预算不是"限制放大"而是"干脆不许重试"。真实系统里的随机过程不会这么整齐。这正是课 9 番外"先怀疑测量方法"铁律的延伸：这次不是测法错，是实现错，但**抓到它的手段相同**。
6. 因为 equal jitter 两次等待的理论范围是 `[0.075, 0.150]`，**本就可能大于 0.1**，断言会偶发失败。错在判据与性质不对应：要验证"随机性"，却用了"大小比较"。正确判据是**多次运行的波动**（`spread > 0.005`），固定值每次相同、jitter 每次不同。
7. 不能。`max_attempts` 只限制**单个调用**的重试次数，控制不了**整体**放大——1000 个对象各重试 3 次，整体就是放大 4 倍。`retry_budget` 是在全局层面封顶。
8. 并发闸门控制**瞬时在飞数**（防尖峰），重试预算控制**总重试量**（防总量放大）。只留一个不够：只有闸门则总量仍可无限累加；只有预算则瞬时仍可全部涌出形成尖峰。二者对应课 9 番外的两个结论——jitter 控尖峰、次数控总量。

</details>

---

## 相关

- **重试理论**：[课 6 番外 4：重试与指数退避](lesson-06-async4-重试与指数退避.md)
- **异步并发**：[课 9：异步客户端与并发](lesson-09-异步客户端与并发.md)
- **未实测项来源**：[课 9 番外：异步三个未实测项](lesson-09-async-异步三个未实测项.md)
- **错误处理**：[课 5：错误处理与健壮性](lesson-05-错误处理与健壮性.md)
- **patch 与 409**：[课 3：CRUD 与 patch 语义](lesson-03-CRUD与patch语义.md)
- **返回**：[子教程 overview](../overview.md)

> **关于 APF 造真 429**：课 9 番外已证本机打不出 429（请求落 `global-default` 是 Queue 型）。要亲手造出真 429 需修改集群 APF 配置（把某 PriorityLevel 改为 Reject 或新建低配额 FlowSchema），属**改环境操作**，需你明确授权后才会执行。
