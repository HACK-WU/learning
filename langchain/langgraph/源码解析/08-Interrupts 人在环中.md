# 源码解析 08：`interrupt()` 抛出后执行流怎么被接住与恢复

> 对应：[课 8 Interrupts 人在环中](../stages/3-可控性与人在环中/lessons/08-Interrupts%20人在环中.md)
> 源码版本：**langgraph 1.2.11**（本机 `../langchain/playground/.venv/lib/python3.12/site-packages/langgraph/`）
> 阅读方式：先给结论 → 再跟调用链 → 最后回扣课上的实测现象

## 一句话结论

**`interrupt()` 不是"挂起线程"，而是抛 `GraphInterrupt` 异常；Pregel 循环捕获它、把 `Interrupt` 对象写进 checkpoint 的 `tasks`，然后正常返回。恢复时节点重跑，`interrupt()` 这次从 `scratchpad.resume` 里按下标取回答案。**

---

## 一、三层调用链

```
interrupt(value)                       types.py:851
   ├─ 有 resume 值？ → return scratchpad.resume[idx]      types.py:957-963
   ├─ 有 null_resume？ → 追加后 return v                  types.py:964-968
   └─ 都没有 → raise GraphInterrupt((Interrupt(...),))    types.py:967
                          │
                          ▼
           GraphInterrupt(GraphBubbleUp)   errors.py:102 / :50
                          │
                          ▼
              Pregel 循环捕获 → 写 checkpoint → 返回
```

---

## 二、`interrupt()` 本体（types.py:851-970）

```python
def interrupt(value: Any) -> Any:
    conf = get_config()["configurable"]
    scratchpad = conf[CONFIG_KEY_SCRATCHPAD]
    idx = scratchpad.interrupt_counter()          # ① 本次是第几个 interrupt

    if scratchpad.resume:                          # ② 之前存过答案？
        if idx < len(scratchpad.resume):
            conf[CONFIG_KEY_SEND]([(RESUME, scratchpad.resume)])
            return scratchpad.resume[idx]          # ← 按下标取回

    v = scratchpad.get_null_resume(True)           # ③ 本次带进来的答案？
    if v is not None:
        assert len(scratchpad.resume) == idx
        scratchpad.resume.append(v)
        conf[CONFIG_KEY_SEND]([(RESUME, scratchpad.resume)])
        return v

    raise GraphInterrupt(                          # ④ 都没有 → 抛异常
        (Interrupt.from_ns(value=value, ns=conf[CONFIG_KEY_CHECKPOINT_NS]),)
    )
```

### 三个关键设计

**① `interrupt_counter()` 是"第几次调用"的计数器**

这解释了一个课上实测的现象——**循环里三次 `interrupt()`，每次 resume 只推进一个**：

```python
for it in ["A", "B", "C"]:
    ans = interrupt(f"处理 {it}?")     # 第一次 idx=0，第二次 idx=1...
```

第一次跑：idx=0，无 resume → 抛异常问 A。
第二次跑：idx=0，resume 里有 1 个值 → **返回那个值**（不再问 A）；循环继续，idx=1 无值 → 抛异常问 B。

> ✅ **"前面答过的会被记住"** 就是 `scratchpad.resume` 这个列表按 index 匹配实现的。

**② `assert len(scratchpad.resume) == idx` 是一条一致性校验**

它保证"已经答过的数量"必须等于"当前是第几个"——**如果跳号就崩**。这也是为什么必须按顺序 resume。

**③ 抛出的是 `GraphInterrupt`，不是普通异常**

```
errors.py:50   class GraphBubbleUp(Exception)     # 可冒泡的基类
errors.py:102  class GraphInterrupt(GraphBubbleUp)
```

`GraphBubbleUp` 这个名字直白说明设计意图：**它要能穿过子图边界往上冒**（课 10 会再遇到）。

---

## 三、`Interrupt` 对象（types.py:575）

```python
@dataclass(init=False, slots=True)
class Interrupt:
    value: Any        # 你传给 interrupt() 的东西
    id: str           # 自动生成的唯一 id
```

> ✅ 这对应课上实测的：
> ```
> Interrupt(value={'问': '要付 100 元，批准吗？'}, id='0e14aa7357cbd56bd29443f262c815fc')
> ```

docstring 里写着版本变迁（v0.6.0 移除了 `ns` / `when` / `resumable` / `interrupt_id`）——**老教程里的 `interrupt_id` 已经不能用了**。

---

## 四、为什么恢复是"重跑"而不是"续跑"

从源码看，答案很清楚：

1. `interrupt()` 是**抛异常**，Python 的异常会**一路退栈到捕获处**——节点函数的剩余部分（包括 `return`）**根本没有执行**；
2. 因此 checkpoint 里那个 task 的状态是**"待执行"**（课上实测 `next = ('pay',)`）；
3. 恢复时 Pregel 循环**重新调度这个 task**，节点函数从头执行；
4. 这次 `interrupt()` 因为 `scratchpad.resume` 有值而**不再抛异常，直接返回**。

> ✅ 这解释了课上实测的两个现象：
> - **`values` 是原样**（`approved` 还是空）——`return` 没跑到；
> - **副作用执行 2 次**——`charge()` 在 `interrupt()` 之前，重跑就又执行一次。

---

## 五、回扣课上的其余实测现象

| 课上现象 | 源码解释 |
|---|---|
| 不挂 checkpointer 不报错，但 `get_state` 抛 `ValueError` | `interrupt()` 抛异常与 checkpointer 无关；但写/读 checkpoint 需要它 |
| `Command(resume=)` 不挂 checkpointer 抛 `RuntimeError` | resume 值要写进 checkpoint，没有存档器就无处可写 |
| 静态中断 `st.interrupts` 是 `()` | 静态中断不经过 `interrupt()`，没构造 `Interrupt` 对象 |
| 静态中断的 resume 值被丢弃 | 没有 `interrupt()` 调用去消费 `scratchpad.resume` |
| resume 类型原样透传 | `return scratchpad.resume[idx]` 直接返回，无类型转换 |
| `update_state` 不消中断、反复中断 | `update_state` 只改状态，不动 `scratchpad.resume`；节点重跑时 `interrupt()` 仍然无值可返回 → 再抛 |

---

## 六、一个避坑结论

源码里这一行值得记住：

```python
v = scratchpad.get_null_resume(True)
if v is not None:
```

**判断用的是 `is not None`**——所以 **`resume=None` 在语义上等于"没带答案"**，会走到抛异常分支……但课 8 实测 `Command(resume=None)` 却抛了 `UnboundLocalError`（`pregel/_loop.py:927` 的 `resume_is_map` 未初始化）。

> ⚠️ 这是 **Pregel 循环里 resume 预处理代码的缺陷**，不是 `interrupt()` 本身的问题。
> ✅ **规避：别传 `None`，用 `""` / `False` / `{"decision": "reject"}` 之类明确的值。**

---

## 七、小结

| 想搞清楚什么 | 看哪里 |
|---|---|
| `interrupt()` 怎么决定"返回还是抛" | `types.py:851-970` |
| 循环里答过的怎么被记住 | `scratchpad.interrupt_counter()` + `scratchpad.resume[idx]` |
| 抛的异常是什么、能不能冒泡 | `errors.py:50` `GraphBubbleUp` / `:102` `GraphInterrupt` |
| 前端拿到的问题对象长什么样 | `types.py:575` `Interrupt`（`value` + `id`） |
| 为什么必须重跑 | 异常退栈 → task 仍是"待执行" → 重新调度 |

🔬 **读源码的收获**：`interrupt()` 的实现只有 20 行左右，核心就是**"一个计数器 + 一个答案列表"**。理解了 `scratchpad.resume[idx]` 这个下标匹配，课 8 那些看似零散的实测现象（循环逐个推进、类型透传、update_state 不消中断）就全都说得通了。
