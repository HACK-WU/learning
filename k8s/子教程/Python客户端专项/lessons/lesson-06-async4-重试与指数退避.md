# 课 6 番外 4：重试与指数退避 —— 让调谐扛过临时故障

> 前置：[课 6：watch · informer · 调谐循环](lesson-06-watch与informer.md)、[番外 1：异步改写](lesson-06-async-调谐循环的异步改写.md)
> 环境：k8s v1.34.0（`kind-k8s-c1`）；`kubernetes-asyncio` 36.1.0
> 代码：[retry_backoff.py](../assets/lesson06-async/retry_backoff.py)、[test_retry_backoff.py](../assets/lesson06-async/test_retry_backoff.py)
> 本文所有数字均为 2026-09-29 本机实测，未实测处已显式标注。

---

## 第一部分：番外 1 留了个坑

番外 1 的 worker 是这样处理失败的：

```python
try:
    async with sem:
        await reconcile_one(v1, ns, name, stats, delay=delay)
except Exception:
    stats["errors"] += 1        # ← 记一笔，然后呢？
finally:
    queue.done(name)
```

**然后就没有然后了。** 对象出队 → 失败 → 计数 → 消失。

这意味着：**一次临时故障（网络抖动、apiserver 重启、503）会让这个对象永远不再被调谐**。而控制器模式的核心承诺是"持续逼近期望状态"——现在它连重试都不做，承诺直接作废。

实测对照（注入前 2 次 503、第 3 次成功）：

```text
注入：前 2 次返回 503，第 3 次成功
结果: r='ok' ok=True  实际调用 3 次
耗时: 0.263s   stats={'class_retryable': 2, 'slept': 2, 'attempts': 3}

对照（番外 1 的裸 except 丢弃版）:
  调用 1 次后 → stats={'errors': 1}
  → 对象被丢弃，后续再也不会被调谐 = 永久状态漂移
```

---

## 第二部分：不是所有错误都该重试

把错误一视同仁地重试，是把小故障放大成故障的方法。先分类：

| 类别 | 典型 | 该不该重试 | 理由 |
|------|------|-----------|------|
| `gone` | **404** | ❌ | 对象已被删除，重试一万次也是 404 |
| `fatal` | **422 / 400 / 403** | ❌ | 请求本身错，得改代码，重试无用 |
| `retryable` | **409 / 5xx / 超时** | ✅ | 服务端暂时不可用，等一会儿就好 |

实测 K8s 真实行为：

```text
场景                    实测结果        判定
replace 带旧 rv          HTTP 409       重试有意义（重读 rv）
非法名称 create          HTTP 422       不该重试（改代码才有用）
读不存在的对象            HTTP 404       不该重试（对象已删）
同对象连续调谐两次        reconciled → no_op   幂等
```

分类正确性的价值是**省额度**——实测 404 只调用 1 次就放弃：

```text
实际调用次数 = 1  stats={'class_gone': 1, 'giveup_gone': 1}
→ ✓ 1 次即放弃
```

> 补充：409 只在用 `replace`（带 `resourceVersion`）时才是冲突。番外 1 已改用 `patch`，所以实践中 409 几乎不出现——分类表里保留它是为了完整性。

---

## 第三部分：🚨 天真重试会造成队头阻塞

最容易写出来的重试是这样的：

```python
for _ in range(10000):
    try:
        await always_fail(name)
        break
    except Exception:
        await asyncio.sleep(0.1)     # ← worker 在这里睡死了
```

**问题：worker 在 `sleep` 期间什么也干不了。** 失败对象占着 worker，后面的对象排不上队。

实测（2 个永远失败的坏对象 + 4 个正常对象，**坏对象先入队**）：

```text
方案                     好对象完成   全部完成耗时   判定
天真(worker内sleep)        0/4        未完成        队头阻塞
重试队列(延迟重入队)        4/4        0.02s        ✓ 正常

天真版 坏对象调用次数: 60
重试版 坏对象调用次数: 8
```

**天真版 4 个好对象一个都没完成**——两个坏对象把 worker 占死了。

> ### 🚨 我在这题上犯的测法错误（本课程第五次）
>
> 第一版我拿「3 秒内的总调用次数」当指标，算出"天真版 30 vs 重试队列版 40，下降 -33%"——**一个负数**，荒谬。
>
> 错在：**调用次数根本不是队头阻塞的度量**。队头阻塞的定义是"前面的坏任务挡住后面的好任务"，正确度量是**好对象的完成数**。
>
> 更讽刺的是：修复后重入队真正生效，调用变多恰恰说明重试在工作，我却把它当成了"性能退化"。**又是尺子错了，不是代码错了。**

### 正确做法：worker 不等待，交给队列延迟重入队

```python
# 失败 → 安排延迟重入队 → worker 立刻去干下一个
await queue.requeue_after(name, policy.delay(attempt))
```

这样退避期间 worker 是空闲的，可以去处理其他对象。

---

## 第四部分：指数退避 + jitter

### 为什么要退避

固定间隔重试会让请求持续以相同速率打到 apiserver——对方还没恢复，你还在加压。指数退避让重试间隔快速拉大，给对方恢复时间。

```python
v = min(base * (2 ** attempt), cap)
```

### 为什么必须加 jitter

这是本文**最值得记住的一点**。实测 100 个对象同时失败，第 3 次重试的时刻分布：

```text
jitter         跨度(s)     min      max     判定
none           0.0000     0.700    0.700    惊群！
full           0.5668     0.088    0.655    已打散
equal          0.2834     0.394    0.677    已打散
```

**无 jitter 时跨度恒为 0.0000s**——100 个请求在**同一瞬间**打到 apiserver。

这就是**惊群（thundering herd）**：如果 1000 个对象同时因为 apiserver 重启而失败，它们会在完全相同的时刻一起重试，把刚要恢复的 apiserver 再次打垮，然后再次一起失败、再次一起重试——**自我维持的故障循环**。

`equal jitter`（AWS 推荐）的公式：

```python
v = min(base * (2 ** attempt), cap)
return v / 2 + random.uniform(0, v / 2)
```

一半固定（保证下界，不会等太久）+ 一半随机（打散）。实测把跨度从 0 拉到 0.2834s。

---

## 第五部分：🚨 自己踩的四个坑（比理论更有价值）

实现过程中连续出四个缺陷，**每一个都是"程序不报错但功能已失效"**。这和番外 1 的 `await queue.add()`、番外 3 的 `?watch=true` 静默退化是同一类病。

### 坑 1：`retry_async` 返回 `(None, False)` → 失败被静默忽略

```python
_, ok = await retry_async(...)     # 调用方忘了检查 ok
```

实测症状：`requeued=0, dropped=0`——重入队路径**根本没被触发**。

**修复：放弃时 `raise`，而不是返回失败标志。**

```python
if kind in ("gone", "fatal"):
    stats[f"giveup_{kind}"] += 1
    raise                           # 强迫调用方处理
```

> 教训：返回"失败标志"允许调用方忘记处理；`raise` 不允许。**契约设计要让错误难以被忽略。**

### 坑 2：重入队被自己的条件判断吞掉

```python
async def _later():
    await asyncio.sleep(delay)
    if name in self._pending:      # ← 恒为 False
        self._q.put_nowait(name)
```

调用方 `done()` 已经把 `name` 从 `_pending` 里 discard 了，所以这个条件**永远不成立**。

实测症状：`requeued=4` 但**每个对象只调用了 1 次**，之后再也没出现。

**修复：用独立的 `_scheduled` 集合标记"已安排重入队"，不依赖 `pending`。**

### 坑 3：`done()` 清空重试计数 → 上限形同虚设

修完坑 2 后从"完全不重试"翻到"每对象 254 次"——**修过头了**。

根因：`done()` 会 `pop` 掉 `_counts`，导致重试计数永远归零，`max_requeues` 永远达不到。

**修复：把 `done()` 拆成两个语义。**

```python
def done(self, name):        # 彻底处理完：清空计数
def task_done(self, name):   # 仅本次出队结束：保留计数
```

### 坑 4：`finally` 在 `continue` 时也会执行

我以为写了 `continue` 就能跳过收尾：

```python
try:
    ...
    continue                 # ← 我以为跳过了
finally:
    queue.done(name)         # ← 实际照样执行！
```

**Python 的 `finally` 在 `continue` / `break` / `return` 时都会执行。** 所以重入队路径上的 `continue` 依然会走到 `done()`，把计数清掉——这正是 254 次的根因。

**修复：不用 `finally`，三条路径各自显式收尾。**

```python
if requeued:
    queue.task_done(name)    # 保留计数
else:
    queue.done(name)         # 彻底清除
```

### 修复后的收敛结果

```text
4 个持续失败对象，max_requeues=3，观察 4 秒

对象       调用次数
obj-0      4
obj-1      4
obj-2      4
obj-3      4

队列 stats: {'requeued': 12, 'task_done': 16, 'dropped_max_requeues': 4}

判定:
  1. 重入队发生: ✓ (requeued=12)
  2. 上限被触发: ✓ 会放弃 (dropped=4)
  3. 调用有界: 每对象 4.0 次（上限 1+3=4 次/对象）
```

**每对象恰好 4 次（1 次首次 + 3 次重入队），严格有界。**

---

## 第六部分：端到端

注入故障：让 `patch` 前 6 次返回 503，之后恢复正常。

```text
注入前 6 次 patch 返回 503，之后正常
最终: [('rb-0','true'), ('rb-1','true'), ('rb-2','true'),
       ('rb-3','true'), ('rb-4','true')]
stats: {'class_retryable': 6, 'slept': 6, 'slept_seconds': 0.65,
        'reconciled': 5, 'recovered_at_2': 3, 'attempts': 11,
        'ok': 5, 'processed': 5}

判定: ✓ 5/5 最终调谐成功
```

`recovered_at_2: 3` 表示有 3 个对象是在**第 3 次尝试**（attempt=2）时恢复的——它们第一次、第二次都撞上了 503，靠重试活了下来。

放在番外 1 的版本里，这 3 个对象会被永久丢弃。

---

## 速览

| 项 | 结论 | 证据 |
|----|------|------|
| 番外 1 的坑 | 失败后**丢弃对象** → 永久状态漂移 | 对照实测 1 次即丢 |
| 错误分类 | 404/422 不重试；409/5xx/超时 重试 | 7 类全对，404 只调 1 次 |
| 🚨 队头阻塞 | 天真版 **0/4** 好对象完成；重试队列版 4/4 | 重写测法后实测 |
| 🚨 惊群 | 无 jitter 时 100 对象跨度 **0.0000s** 同时重试 | 三种 jitter 对比 |
| 坑1 返回失败标志 | 放弃时 `raise`，强迫调用方处理 | `requeued=0` → 修复 |
| 坑2 条件恒假 | 用 `_scheduled` 独立标记 | 1 次 → 修复 |
| 坑3 计数清零 | 拆 `done()` / `task_done()` | 254 次 → 4 次 |
| 坑4 finally+continue | 不用 finally，三路径显式收尾 | 同上 |
| 收敛 | 每对象恰好 4 次，`dropped=4` | 实测 |
| 端到端 | 5/5 成功，`recovered_at_2: 3` | 实测 |

---

## 什么时候该用

| 场景 | 建议 |
|------|------|
| 一次性脚本 | 不需要，失败了重跑即可 |
| 控制器 / 长期运行的守护进程 | **必需**，否则临时故障造成永久漂移 |
| 409 冲突 | 重试（重读 rv）；改用 `patch` 可基本避免 |
| 404 | **不重试**，判 `gone` 直接丢弃 |
| 重试仍失败 | 交给**下一次 resync** 兜底，别在内存里无限试 |

⚠️ **重试不是万能的**：它解决"临时故障"，解决不了"代码有 bug"。422/400 重试一万次也是 422，这时候该改代码。

⚠️ **上限必须有界**：无上限的重试会把一个瞬时故障变成永久的资源泄漏。本文用「次数上限 + 队列重入上限 + 可选 deadline」三重保险。

---

## 小测

1. 为什么番外 1 的 `except Exception: stats["errors"] += 1` 会造成**永久状态漂移**？
2. 为什么 `finally` 里的 `queue.done(name)` 会破坏重试计数（即使写了 `continue`）？
3. 无 jitter 的指数退避在什么场景下会出问题？实测跨度是多少？
4. 404 和 503 分别该不该重试？为什么？
5. 为什么 `retry_async` 放弃时要 `raise` 而不是返回 `(None, False)`？

<details>
<summary>答案</summary>

1. 对象出队后失败，worker 只记一笔 `errors` 就调用 `queue.done()`，对象**再也不会重新入队**。而控制器模式的核心承诺是持续逼近期望状态——一次临时故障（503/网络抖动）就让该对象永远停在漂移状态，承诺失效。实测对照中，注入的临时故障对象在番外 1 版本里调用 1 次即被丢弃。

2. 因为 **Python 的 `finally` 在 `continue` / `break` / `return` 时都会执行**。重入队路径上的 `continue` 依然会走到 `finally: queue.done(name)`，而 `done()` 会 `pop` 掉重试计数 `_counts`，导致 `max_requeues` 永远达不到 → 失败对象无限重试（实测每对象 254 次，远超上限 4 次）。修复方式是不用 `finally`，三条路径各自显式收尾：重入队调 `task_done()`（保留计数），成功或放弃调 `done()`（清除计数）。

3. **惊群（thundering herd）**。大量对象因同一原因（如 apiserver 重启）同时失败时，无 jitter 的退避会让它们在**完全相同的时刻**一起重试，把刚要恢复的 apiserver 再次打垮，形成自我维持的故障循环。实测 100 个对象第 3 次重试的时刻跨度 **0.0000s**（min=max=0.700）。加 `equal jitter` 后跨度 0.2834s。

4. **404 不重试**——对象已被删除，重试多少次都是 404（判 `gone`，实测只调用 1 次就放弃）。**503 要重试**——服务端暂时不可用，等一会儿可能就恢复了。`equal jitter` 退避正是为它准备的。

5. 返回 `(None, False)` 允许调用方**忘记检查**，失败被静默忽略（实测症状：`requeued=0, dropped=0`，重入队路径根本没触发）。`raise` 强迫调用方用 `except` 处理，**让错误难以被忽略**——这是契约设计的原则：错误应该显式，不该是可忽略的返回值。

</details>

---

## 课程导航

- **前置**：[课 6：watch · informer · 调谐循环](lesson-06-watch与informer.md)
- **番外 1**：[调谐循环的异步改写](lesson-06-async-调谐循环的异步改写.md)
- **番外 2**：[多副本选主 leaderelection](lesson-06-async2-多副本选主leaderelection.md)
- **番外 3**：[SharedInformer 共享 watch](lesson-06-async3-SharedInformer共享watch.md)
- **相关**：[课 7：自定义资源与动态客户端](lesson-07-自定义资源与动态客户端.md)
- **返回**：[Python 客户端专项总览](../overview.md)

---

## 评审结论（2026-09-29）

本文由主 agent 内联评审（pedagogy + learner 双视角，独立性受限），P0 = 0。

**实测抓出实现缺陷 4 个（全部为"程序不报错但功能已失效"类）**：
① `retry_async` 返回 `(None, False)` 致调用方忽略失败（`requeued=0`，重入队路径未触发）→ 改为放弃时 `raise`；
② 重入队条件 `if name in self._pending` 恒为 False（`done()` 已 discard），`requeued=4` 但每对象仅调用 1 次 → 改用独立 `_scheduled` 集合；
③ `done()` 清空重试计数致 `max_requeues` 永不可达，修复后从"不重试"翻到"每对象 254 次" → 拆分为 `done()`（彻底清除）与 `task_done()`（保留计数）；
④ `finally` 在 `continue` 时仍执行，重入队路径照样走到 `done()` 清空计数（254 次之根因）→ 弃用 `finally`，三路径显式收尾。修复后收敛为**每对象恰好 4 次**（1 首次 + 3 重入队），`dropped=4`，严格有界。

**测法错误 1 处（本课程第五次应验"先怀疑测量方法"）**：Q3 首版以「3 秒内总调用次数」度量队头阻塞，得出"下降 -33%"的荒谬结论。根因是**调用次数不是队头阻塞的度量**——其定义为"坏任务挡住好任务"，应为**好对象完成数**。重写后：天真版 **0/4** 好对象完成（队头阻塞坐实），重试队列版 4/4 且 0.02s 完成，坏对象调用 60 → 8（降 87%）。

**核心实测结论**：错误分类 7 类全对（404 仅调用 1 次即放弃）；惊群实测 100 对象第 3 次重试跨度 **0.0000s**（无 jitter）vs 0.2834s（equal jitter）；端到端注入前 6 次 503，5/5 最终调谐成功，`recovered_at_2: 3` 表明 3 个对象靠重试存活——这些在番外 1 版本里会被永久丢弃。

**验证通过项**：`py_compile` 全部通过；四个测试脚本实测输出与讲义引用数字逐项对齐；测试 ns `py-lesson06-retry` / `-retry2` / `-retry3` / `-retry4` 均已删除；讲义内敏感信息 0 命中。

**未实测标注 1 处**：409 冲突在改用 `patch` 后实践中几乎不出现，分类表保留该项仅为完整性，未做 patch 场景下的 409 注入实测。
