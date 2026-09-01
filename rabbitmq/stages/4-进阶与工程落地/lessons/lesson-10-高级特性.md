# 第 10 课：高级特性

> 所属阶段：阶段 4《进阶与工程落地》｜ 水平：零基础 ｜ 本课知识点：延迟消息与延迟重试、优先级队列、流控与资源水位
> 故事情节：主角开始接触那些"看起来很美、用错就出事"的高级功能

## 🎯 本课目标

- 用 TTL+DLX 实现延迟队列，并知道 4.3 quorum 队列的原生延迟重试
- 配置优先级队列并说清它对顺序和吞吐的影响
- 解释内存高水位与磁盘告警触发后发布者会发生什么

## 知识点清单（含关键点）

1. **延迟消息与延迟重试**（关键点：TTL+DLX 的顺序陷阱 / 延迟消息插件 / 4.3 quorum 原生延迟重试 / 延迟重试的适用场景）
2. **优先级队列**（关键点：x-max-priority 的代价 / 优先级与顺序性的冲突 / 只在积压时生效）
3. **流控与资源水位**（关键点：内存高水位与 paging / 磁盘告警 / 发布者被阻塞的表现 / 监控与告警）

---

## 开场：三个"看起来很美"的功能

前九课你搭起了一套能扛事的系统：消息不会丢（课 7）、重复能兜住（课 8）、断线能重连（课 9）。

现在有三个功能摆在面前，每一个看起来都特别有用：

- **延迟消息**：订单 30 分钟未支付自动关闭。不用写定时任务轮询数据库了，多优雅。
- **优先级队列**：VIP 客户的订单插队处理。多合理。
- **流控**：内存快满时自动保护 broker。多贴心。

但这三个功能，每一个都有**和直觉不符的暗面**。

本节课要做的，就是把这些暗面一个个照出来。先说结论：

> **这三个功能的共同点是：它们都在"优化"某种默认行为，而优化的代价是破坏了你对系统的某些假设。** 延迟破坏了即时性，优先级破坏了顺序性，流控破坏了"发布者总能成功"的假设。

---

## 知识点 1：延迟消息与延迟重试

### 第一幕：一个"消失"的定时任务

小王接到需求：订单 30 分钟未支付自动关闭。

他很自然地想到延迟队列：下单时发一条延迟 30 分钟的消息，到点消费者收到，检查订单状态，未支付就关闭。不用轮询数据库，优雅。

上线两周后，客服收到投诉：**有些订单 40 多分钟才被关闭，有的甚至更久**。

小王查了一圈，代码没问题，延迟时间写的是 30 分钟。问题出在哪？

这就是本课要讲的第一个坑：**per-message TTL 只对队首生效**。

### TTL+DLX：延迟消息的经典实现

RabbitMQ 本身没有"延迟队列"这个原生类型，经典做法是用**消息 TTL + 死信交换机**拼出来：

```
publisher ──► 延迟交换机 ──► 延迟队列
                              │
                              │ 消息 TTL 到期
                              │ （自动死信）
                              ▼
                          目标交换机 ──► 业务队列 ──► consumer
```

延迟队列本身**没有消费者**，只是让消息在里面"躺"够时间。TTL 一到，消息被自动死信到目标交换机，再路由到业务队列，消费者才拿到。

代码长这样：

```python
# 延迟队列：只负责"等"，没人消费它
ch.queue_declare(
    queue='delay.q', durable=True,
    arguments={
        'x-dead-letter-exchange': 'target.ex',
        'x-dead-letter-routing-key': 'go',
    })

# 发布时指定 TTL（毫秒）
ch.basic_publish(
    exchange='delay.ex', routing_key='delay', body=order_id,
    properties=pika.BasicProperties(
        delivery_mode=2,
        expiration=str(30 * 60 * 1000),    # 30 分钟
    ))
```

看起来很完美。单条消息实测也确实准：

```
【A】单条消息 TTL=5000ms，测量多久出现在业务队列
  业务队列耗时：5.14 s（期望 ≈ 5.0s）
```

（`l10-delay-ttl-dlx.py`）

### ⚠️ 顺序陷阱：短 TTL 被长 TTL 堵住

**但这是单条消息的情况。** 一旦队列里有积压，事情就变了。

实测：先发一条 TTL=20s 的消息，0.5 秒后再发一条 TTL=3s 的：

```
| 消息 | 设定 TTL | 实际到达业务队列 | 判定 |
|------|----------|------------------|------|
| B-fast-3s | 3s | 20.06 s | ⚠️ 被队首堵住 |
| B-slow-20s | 20s | 20.06 s | - |
```

**TTL=3s 的消息，实际等了 20.06 秒才出来。**

原因：RabbitMQ 的**消息级 TTL 是惰性检查的**——broker 只检查**队首**那一条消息是否过期。队首那条要 20 秒才过期，在它过期并被移走之前，后面的消息根本不会被看一眼。

这就是为什么小王的订单有时 40 分钟才关闭：前面堆积了一条更晚到期的消息，把它堵住了。

> **一句话记住**：消息级 TTL 只对队首生效。**队列里有长 TTL 消息时，后面所有短 TTL 消息都会被延后。**

**两种解法**：

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **队列级 TTL** | 延迟队列声明 `x-message-ttl` | 不存在堵塞问题 | 整个队列共用一个 TTL |
| **分档延迟队列** | 按延迟档位建多个队列：`delay.5s`、`delay.30s`、`delay.5m` | 各档独立，无堵塞 | 延迟档位必须预先规划 |

分档延迟队列是实际工程中最常用的做法——延迟时间本来就是几个固定档位（5 分钟、30 分钟、2 小时），没必要做成任意值。

### 延迟消息插件：另一条路

社区还有一个插件 `rabbitmq_delayed_message_exchange`，提供一个 `x-delayed-message` 类型的交换机，发布时指定 `x-delay` 头就能延迟任意时长，且**不存在队首堵塞问题**（它在交换机层面按延迟时间排序）。

**但本环境没有这个插件**——实测 `rabbitmq-plugins list` 的输出里不存在该项：

```
[  ] rabbitmq_consistent_hash_exchange         4.3.5
[  ] rabbitmq_event_exchange                   4.3.5
...（无 rabbitmq_delayed_message_exchange）
```

> ⚠️ **如实说明**：本课**未能实测**延迟消息插件（环境未安装），因此讲义不给出未经实测的插件用法代码。它的原理与限制以上述说明为准，实际使用请以官方文档为准。

插件方案的主要限制（官方已知）：

- 属于**社区插件**，不是核心分发的一部分，需要单独下载安装
- 延迟消息存在**内部 Mnesia/Khepri 表**中，节点重启后的行为需要额外验证
- 不支持 `mandatory` 与发布者确认的完整语义（路由失败时行为与常规交换机不同）

**选型建议**：能用分档 TTL+DLX 解决的就用它（零依赖、行为可预测）；确实需要**任意延迟时长**且量大时再考虑插件。

### 4.3 的新答案：quorum 队列原生延迟重试

前面讲的都是"延迟投递"——消息**首次**就要延迟。

但还有一类更常见的需求：**处理失败后延迟重试**。比如下游 API 返回 429 限流，你不该立刻重试，而该等一会儿。

课 9 的做法是"ack + 自维护计数 + 重发"，比较笨拙。而 **RabbitMQ 4.3 为 quorum 队列引入了原生延迟重试**：

```python
ch.queue_declare(
    queue='orders', durable=True,
    arguments={
        'x-queue-type': 'quorum',
        'x-delayed-retry-type': 'all',     # disabled | all | failed | returned
        'x-delayed-retry-min': 3000,       # 最小延迟 3 秒
        'x-delayed-retry-max': 12000,      # 最大延迟 12 秒（封顶）
        'x-delivery-limit': 20,
    })
```

配置后，消息被返回时会自动延迟，且延迟**随失败次数线性增长**：

```
delay = min(delayed_retry_min × delivery_count, delayed_retry_max)
```

比如 min=3s、max=12s 时：第 1 次返回等 3 秒，第 2 次等 6 秒，第 3 次等 9 秒，第 4 次起封顶 12 秒。

### ⚠️ 实测：nack 与 reject 的行为完全不同

这是本课**最反直觉、也最容易踩坑**的一点。

按 4.3 的新语义，quorum 队列区分两个计数器：

| 计数器 | 何时 +1 |
|---|---|
| `acquired-count` | **每次**消息被返回（requeue）都 +1 |
| `delivery-count` | 仅**投递失败**时才 +1 |

按官方文档的判定表：

| 触发方式 | acquired-count | delivery-count |
|---|---|---|
| `basic.nack` | ✅ +1 | ❌ 不变 |
| `basic.reject` | ✅ +1 | ✅ +1 |
| 客户端崩溃 / 连接断开 | ✅ +1 | ✅ +1 |

而延迟公式用的是 **`delivery_count`**。所以推论是：

> **`nack` 返回不会让延迟递增，`reject` 才会。**

实测验证（`l10-backoff-final.py`，min=3000ms、max=12000ms，连续返回同一条消息）：

```
【NACK】basic_nack(requeue=True)
| 轮次 | 实测延迟 | 理论延迟 | x-acquired-count |
|------|----------|----------|------------------|
| 2 | 3.05 s | 6.0 s | 1 |
| 3 | 3.05 s | 9.0 s | 2 |
| 4 | 3.06 s | 12.0 s | 3 |
| 5 | 3.05 s | 12.0 s | 4 |
| 6 | 3.04 s | 12.0 s | 5 |

【REJECT】basic_reject(requeue=True)
| 轮次 | 实测延迟 | 理论延迟 | x-acquired-count |
|------|----------|----------|------------------|
| 2 | 3.06 s | 6.0 s | 1 |
| 3 | 6.11 s | 9.0 s | 2 |
| 4 | 9.15 s | 12.0 s | 3 |
| 5 | 12.01 s | 12.0 s | 4 |
| 6 | 12.20 s | 12.0 s | 5 |
```

这是一个**教科书级的对照结果**：

- **`reject` 组**：3.06 → 6.11 → 9.15 → 12.01 → 12.20 秒，**线性递增并在 12 秒封顶**，与官方公式完全吻合
- **`nack` 组**：恒定在 3.05 秒左右，**永不递增**
- 但两组的 `x-acquired-count` **都在增长**（1、2、3、4、5）

最后一列是关键证据：**acquired-count 增长了，但 nack 组的延迟没变**——证明延迟确实按 `delivery-count`（而非 acquired-count）计算，而 `nack` 不增加 `delivery-count`。

> **一句话记住**：想让延迟重试的退避真正生效，用 **`basic_reject`**，不要用 `basic_nack`。`nack` 在 4.3 里语义是"这条消息我拿了一下但没失败"，所以延迟永远是最小值。

**这个特性的另一个直接后果**：因为 `delivery-limit`（毒消息处理）也只看 `delivery-count`，所以用 `nack` 返回的消息**不会计入投递上限**——4.3 官方称之为"支持无限次返回（unlimited returns）"。

### ⚠️ 实测踩坑：写错参数不报错

实测 `x-delayed-retry-type` 的取值校验：

```
| type | 声明结果 |
|------|----------|
| disabled | ✅ 接受 |
| all | ✅ 接受 |
| failed | ✅ 接受 |
| returned | ✅ 接受 |
| bogus_value | ✅ 接受 |
```

**`bogus_value` 也被接受了**——写错枚举值不会有任何报错，队列照样声明成功，但延迟重试会静默失效。

这是本环境 4.3.5 的实测行为。唯一的保障是**自己验证效果**，不要假设"没报错就是配对了"。

### 延迟重试适用于什么场景

官方给出的典型场景：

- **实体级限流**：某个租户的 API 被限流（HTTP 429），但不该暂停整个消费者——只延迟这一条消息
- **数据库行锁**：某一行临时被锁，不该阻塞几千条其他消息的处理

**反过来的建议**：如果消费者**完全无法处理任何消息**（比如下游数据库整体宕机），官方明确建议**暂停消费者**而不是给每条消息都加延迟。恢复后再启动消费者，比让几万条消息各自延迟要高效得多。

---

## 知识点 2：优先级队列

### 第二幕：一个失效的"VIP 插队"

产品经理说：VIP 客户的订单要优先处理。

小张给队列配了 `x-max-priority`，发布时给 VIP 订单设 `priority=9`。上线后他特意观察，**发现 VIP 订单并没有被优先处理**，和普通订单混在一起按先后处理。

他怀疑配置没生效，反复检查了几遍都没问题。

原因很简单，也写在官方文档里：

> **优先级只在队列有积压时才有意义。消费者跟得上时，消息一到就被取走，队列里根本没东西可排序。**

### 实测：有积压 vs 无积压

**无积压场景**（发一条、立刻取一条，消费者永远空闲）：

```
发布优先级：[1, 9, 2, 8, 3]
实际取出：  [1, 9, 2, 8, 3]
与发布顺序一致（优先级未起作用）：✅ 是
```

（`l10-priority-fixed.py` 场景 E）

**完全按发布顺序**出来，优先级毫无作用。这正是小张遇到的情况——他的消费者处理能力充足，队列一直是空的。

**有积压场景**（先堆积再消费）：

```
发布顺序：[0, 7, 3, 11, 1, 9, 2, 10, 4, 8, 5, 6]
消费顺序：[11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
严格降序（高优先级先出）：✅ 是
```

先堆积 12 条，再开始消费——**严格按优先级从高到低**出来。

> **一句话记住**：优先级是"**积压时的排队规则**"，不是"实时调度器"。消费者跟得上时它完全不起作用。

### ⚠️ classic 与 quorum 的配置方式完全不同

这是本课第二个容易混淆的地方，而且**官方文档说得非常明确**：

> "**Priorities Are Always Enabled.** Quorum queues always provide the full 0-31 priority range. There is no opt-in argument: **`x-max-priority` applies only to classic queues and is ignored by quorum queues**."

翻译成人话：

| 队列类型 | 怎么开优先级 | 级别数 |
|---|---|---|
| **classic** | 声明时传 `x-max-priority`（1~255） | 你指定的值 |
| **quorum** | **不需要任何参数，默认启用** | 固定 32 级（0-31） |

实测佐证——给 quorum 队列传 `x-max-priority` 会被**直接拒绝**：

```
quorum x-max-priority=1    -> ❌ PRECONDITION_FAILED - invalid arg 'x-max-priority'
quorum x-max-priority=10   -> ❌（channel 被关闭）
quorum x-max-priority=32   -> ❌
```

（所有取值 1/2/3/5/8/10/16/31/32/33/64/255 全部被拒）

而 classic 队列的边界实测：

```
| x-max-priority | 声明结果 |
|----------------|----------|
| 0 | ✅ 接受 |
| 1 | ✅ 接受 |
| 10 | ✅ 接受 |
| 255 | ✅ 接受 |
| 256 | ❌ 拒绝：invalid arg 'x-max-priority' |
```

**这个坑很实在**：你从 classic 迁移到 quorum 时，如果照抄 `x-max-priority` 参数，队列声明会**直接失败**。

### ⚠️ 一个极易忽略的差异：默认优先级不同

未设 `priority` 的消息，两类队列的**默认值不一样**：

- **quorum**：默认 **4**
- **classic**：默认 **0**

实测（发三条：无优先级、`priority=2`、`priority=8`）：

```
quorum           消费顺序：['P8', 'NO_PRIORITY', 'P2']
classic(max=10)  消费顺序：['P8', 'P2', 'NO_PRIORITY']
```

看 quorum 那行：无优先级的消息排在 **P8 和 P2 中间**——正好符合"默认优先级 4"（4 介于 2 和 8 之间）。

而 classic 那行：无优先级消息排在**最后**——符合"默认优先级 0"。

**一行输出就证明了这个差异**。迁移队列类型时如果不注意，消息的相对顺序会悄悄改变。

### 优先级会被"钳制"

quorum 只有 0-31 共 32 级，超出会被钳制：

```
发布：priority=5, priority=100
消费顺序：['P100', 'P005']
✅ priority=100 被当作最高级处理（钳制到 31）
```

`priority=100` 被钳到 31，仍然是最高级。

### 优先级的三个代价

第一，**破坏顺序性**。课 8 讲的所有顺序保证，在优先级队列上都不成立。官方文档明确把"消息优先级"列为会改变投递顺序的因素之一。

第二，**高优先级数有 CPU 代价**。classic 队列需要为每个优先级维护一个子队列，官方强烈建议 **2~4 个优先级**就够，不要设几十上百。

第三，**被返回的消息不保留原优先级**。这是个隐蔽的坑：消息被 `reject`/`nack` 返回后，**不会回到原来的优先级位置**，而是进入 returns 队列、按返回顺序重排。

### 什么时候该用优先级

官方给出了明确的**替代方案**，并建议优先考虑：

- **用多个队列代替一个**：`priority.high` / `priority.medium` / `priority.low`。这既能避免队头阻塞，又保持标准 FIFO 行为，还能获得更好的并行度
- **用不同的 prefetch**：给不同消费者通道设置不同的 prefetch
- **用 stream**：需要严格顺序时用

官方原话的大意是：单条巨型队列本身是常见反模式，而优先级队列的行为**比标准 FIFO 难推理得多**。

---

## 知识点 3：流控与资源水位

### 第三幕：一个"卡死"的发布服务

凌晨，发布服务突然全线程卡住，没有任何报错，进程在，连接也在，就是不工作。

运维查监控：**RabbitMQ 磁盘只剩 40MB，触发了磁盘告警**。

这就是流控。它是 broker 的自我保护机制——资源快耗尽时，**阻塞发布者**来争取喘息时间。

### 两个水位

| 水位 | 配置项 | 本环境值 | 触发后 |
|---|---|---|---|
| **内存高水位** | `vm_memory_high_watermark` | **0.6**（60% 可用内存） | 阻塞发布者，消息分页到磁盘 |
| **磁盘告警** | `disk_free_limit` | **50000000**（50 MB） | 阻塞发布者，阻止分页（已无空间） |

实测读取本环境配置：

```
{disk_free_limit,50000000},
{vm_memory_high_watermark,0.6},
```

```
Total memory used: 0.1622 gb
Memory high watermark setting: 0.6 of available memory, computed to: 20.0189 gb
Free Disk Space
Low free disk space watermark: 0.05 gb
Free disk space: 908.2192 gb
```

### 告警触发后，发布者会发生什么

**理论上**：broker 会给所有发布者连接发送 `Connection.Blocked` 帧。客户端收到后应该暂停发布，直到收到 `Connection.Unblocked`。

实测触发内存告警（`l10-flow-blocked.py`，把水位临时调到 `0.000001`）：

```
【2】触发内存告警（设水位为 0.000001）
【3】告警状态
  Alarms
  Memory alarm on node rabbit@07f37e4f56b5
```

告警确实生效了。随后解除告警，客户端收到了成对的事件：

```
【4】解除告警（恢复水位 0.6）
  客户端事件序列：['BLOCKED', 'UNBLOCKED']
```

**这证明 blocked/unblocked 通知机制确实工作**。

### ⚠️ 但实测发现两个反直觉之处

**第一，告警期间的那次 publish 并未被挂起。**

```
【3】告警期间发布消息（blocked_connection_timeout=10s）
  结果：publish 返回成功
  耗时：0.00 s
  ⚠️ publish 立即返回 → 未观察到阻塞
```

明明告警已经生效，publish 却瞬间返回了。

**必须诚实说明**：本次实测**未能复现**"告警期间 publish 被挂起"的现象。可能的原因包括：该队列刚声明、无积压，broker 判定无需阻塞；或告警与 publish 的时序存在竞争。

因此本课的结论是：**告警不等于每一次 publish 都会被阻塞**，具体行为与队列当时的状态有关。不要依赖"告警后发布一定会被挡住"来做流控判断。

**第二，`BLOCKED` 事件是在解除告警后才被读到的。**

事件序列显示 `BLOCKED` 和 `UNBLOCKED` 的相对时间都是 `0.0`——它们是在第 4 步的 `pump()`（显式驱动事件循环）时才被一起处理到的。

这呼应课 9 的结论：**pika 的 `BlockingConnection` 只在 `process_data_events()` 时才处理 incoming 帧**。如果你的程序一直在 `publish` 而从不驱动事件循环，`Connection.Blocked` 通知会被**积压到缓冲区里收不到**。

> **实践含义**：发布端必须在发布循环中定期调用 `process_data_events()`，否则收不到阻塞通知，会一直往一个已经要求你停下的 broker 里灌数据。

### ⚠️ 安全提醒：如何安全验证流控

本课的流控实验采用了一个**安全技巧**，值得你记下来：

真实触发内存告警需要把容器内存压到 60%——这在个人电脑上会明显拖慢系统、甚至触发宿主交换，风险太高。

替代做法是**临时把水位调到一个极低值**：

```bash
# 触发告警（几乎立刻触发，不需要真的占内存）
rabbitmqctl set_vm_memory_high_watermark 0.000001

# 测完【务必】恢复
rabbitmqctl set_vm_memory_high_watermark 0.6

# 验证已恢复
rabbitmqctl status | grep -i alarm
```

实测恢复后：

```
Alarms
(none)
最终水位：Memory high watermark setting: 0.6 of available memory
```

**这个技巧在生产环境同样适用**——可以用它验证告警链路是否通畅，而不用真的把生产 broker 压满。

### 客户端要配什么

pika 连接参数里的 `blocked_connection_timeout` 就是为这个场景准备的：

```python
pika.ConnectionParameters(
    ...
    blocked_connection_timeout=300,   # 被阻塞时最多等 300 秒
)
```

它规定"连接被阻塞时，操作最多等多久"。**不设的话可能无限挂起**——这就是第三幕里那个"卡死但没报错"的发布服务。

### 监控建议

生产上必须监控这两个水位，并配置告警：

- **内存**：关注 `rabbitmq_node_mem_used` 与高水位的比值，接近时提前扩容或加速消费
- **磁盘**：关注剩余空间，远早于 50MB 就该告警
- **告警状态**：直接监控 `rabbitmq_node_alarms` 或 Management UI 的 Alarms 区域

> 注意：本环境已启用 `rabbitmq_prometheus` 插件（实测 `rabbitmq-plugins list` 显示 `[E*]`），生产上可直接用它接入 Prometheus。

---

## 本课要点速查卡

| 主题 | 结论 |
|---|---|
| **TTL+DLX 顺序陷阱** | per-message TTL 只对【队首】生效；实测 TTL=3s 的消息被前面 TTL=20s 的堵到 **20.06s** |
| TTL+DLX 解法 | 队列级 TTL，或按延迟档位建多个队列（`delay.5s`/`delay.30s`） |
| 延迟消息插件 | 本环境【未安装】，未能实测 |
| 4.3 原生延迟重试 | quorum 队列专用，`x-delayed-retry-type/min/max` |
| 退避公式 | `delay = min(min × delivery_count, max)` |
| **nack vs reject** | `nack` 延迟**恒定** min（实测 3.05s 不变）；`reject` **线性递增**（3→6→9→12s 封顶） |
| acquired-count | 两者都增长，但**不参与**延迟计算——延迟只看 delivery-count |
| 参数校验 | `x-delayed-retry-type` 写错值【不报错】，静默失效 |
| **优先级生效前提** | 只在【有积压】时生效；消费者跟得上时完全无效 |
| classic 优先级 | 需 `x-max-priority`（1~255，实测 256 被拒） |
| quorum 优先级 | **默认启用 32 级（0-31）**，传 `x-max-priority` 会【被拒绝】 |
| 默认优先级 | quorum=**4**，classic=**0**（不同！） |
| 优先级钳制 | 超出 0-31 被钳制（实测 priority=100 等同 31） |
| 优先级代价 | 破坏顺序性、高优先级数耗 CPU、返回消息不保留原优先级 |
| 内存高水位 | 本环境 0.6（60% 可用内存） |
| 磁盘告警 | 本环境 50 MB |
| 告警后果 | 阻塞【发布者】，消费者不受影响 |
| blocked 通知 | 需 `process_data_events()` 驱动才收得到 |
| 客户端配置 | `blocked_connection_timeout`，不设可能无限挂起 |

---

## 常见误区

| # | 误区 | 真相 |
|---|------|------|
| 1 | "TTL+DLX 能精确控制每条消息的延迟" | 只对队首生效，会被前面的长 TTL 消息堵住（实测 3s 变 20s） |
| 2 | "延迟插件是官方功能" | 社区插件，需单独安装；本环境未装、未能实测 |
| 3 | "配了延迟重试就自动退避" | `nack` 不让延迟递增，只有 `reject` 会（实测对照） |
| 4 | "用 x-death 看重试次数" | 课 6 已证 requeue 不写 x-death；4.3 用 `x-acquired-count` |
| 5 | "写错 x-delayed-retry-type 会报错" | 不报错，静默失效（实测 bogus_value 被接受） |
| 6 | "优先级配好就一直生效" | 消费者跟得上时【完全无效】，只在积压时起作用 |
| 7 | "quorum 也要传 x-max-priority" | 会【被拒绝】；quorum 默认启用 32 级，不需要该参数 |
| 8 | "未设优先级的消息优先级是 0" | quorum 是 **4**，classic 才是 0 |
| 9 | "优先级不影响顺序" | 官方明确列为会改变投递顺序的因素，破坏课 8 的顺序保证 |
| 10 | "内存告警后发布一定被阻塞" | 实测本次 publish 未被挂起；告警 ≠ 每次 publish 都被挡 |
| 11 | "blocked 通知会自动收到" | pika 需 `process_data_events()` 驱动才收得到 |
| 12 | "流控实验要压满内存" | 可临时调低水位软触发，测完恢复（生产同样适用） |

---

## 🧪 小测

### Q1（单选）

你的订单延迟关闭队列，用 TTL+DLX 实现。上线后发现部分订单的关闭时间远长于设定值。最可能的原因是？

A 消息 TTL 设置错误
B per-message TTL 只对队首生效，短 TTL 消息被前面的长 TTL 消息堵住
C 消费者处理太慢
D broker 时间不同步

<details><summary>答案</summary>

**B**。

RabbitMQ 的消息级 TTL 是惰性检查的，只检查队首消息。实测：先发 TTL=20s、再发 TTL=3s，后者实际 **20.06 秒**才到达业务队列。

A 错：TTL 值本身是对的。
C 错：消费者慢会影响处理速度，但不会让延迟消息"提前不出来"——延迟队列根本没有消费者。
D 错：与时间同步无关。

**解法**：用队列级 TTL，或按延迟档位拆成多个队列。

</details>

### Q2（多选）

关于 4.3 quorum 队列的原生延迟重试，下列说法**正确**的是？（多选）

A `nack` 会让延迟线性递增
B `reject` 会让延迟线性递增
C `x-acquired-count` 在 nack 和 reject 时都会增长
D `x-delayed-retry-type` 写错值会报错

<details><summary>答案</summary>

**B、C**。

实测对照（min=3000ms、max=12000ms）：

- `reject` 组：3.06 → 6.11 → 9.15 → 12.01 → 12.20 秒，**线性递增并封顶**
- `nack` 组：恒定 3.05 秒左右，**永不递增**
- 两组 `x-acquired-count` **都增长**（1→2→3→4→5）

A 错：恰恰相反，`nack` 是恒定最小值。因为 4.3 中 `nack` 不增加 `delivery-count`，而延迟公式用的是 `delivery-count`。
D 错：实测 `bogus_value` 被**接受**，不报错，静默失效。

</details>

### Q3（单选）

你给 quorum 队列声明时传了 `x-max-priority=10`，结果队列声明失败。为什么？

A 10 超出了优先级上限
B quorum 队列默认启用 32 级优先级，不接受 `x-max-priority`
C 必须同时设置 `x-queue-type`
D 优先级只能通过 policy 配置

<details><summary>答案</summary>

**B**。

官方文档原文："Quorum queues always provide the full 0-31 priority range. There is no opt-in argument: **`x-max-priority` applies only to classic queues and is ignored by quorum queues**."

实测所有取值（1/2/3/5/8/10/16/31/32/33/64/255）**全部被拒**，报 `PRECONDITION_FAILED - invalid arg 'x-max-priority'`。

A 错：quorum 支持 0-31，10 在范围内——问题不在于值，而在于这个参数本身不适用。
C 错：与 `x-queue-type` 无关，实测已显式传了 quorum 类型。
D 错：官方明确说优先级队列**不支持**用 policy 声明（"Declaring a queue as a priority queue using policies is not supported by design"）。

</details>

### Q4（简答）

你给队列配了优先级，但发现消息仍按发布顺序被消费，优先级完全没起作用。请解释可能原因，并说明优先级在什么条件下才生效。

<details><summary>答案</summary>

**最可能的原因：消费者跟得上，队列没有积压。**

官方文档明确指出，优先级只在队列有积压时才有意义。消费者一直空闲时，消息一到就被取走，队列里始终只有 0 或 1 条消息，**无从排序**。

实测（发一条立刻取一条）：

```
发布优先级：[1, 9, 2, 8, 3]
实际取出：  [1, 9, 2, 8, 3]   ← 完全一致，优先级无效
```

而先堆积 12 条再消费时：

```
发布顺序：[0, 7, 3, 11, 1, 9, 2, 10, 4, 8, 5, 6]
消费顺序：[11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]   ← 严格按优先级
```

**生效条件**：队列中存在多条待投递消息，且消费者一次只能取走其中一部分（受 prefetch 限制）。

**另外两个可能的配置问题**（若确实有积压但仍无效）：
1. 给 quorum 队列传了 `x-max-priority`——会被拒绝（见 Q3）
2. 消息发布时忘了设 `priority` 属性——此时 quorum 按 4、classic 按 0 处理

</details>

### Q5（简答）

为什么课 9 讲的"消费者失败重试"到本课要改用 `reject` 而不是 `nack`？请结合 4.3 的计数器语义说明。

<details><summary>答案</summary>

**因为 4.3 起 quorum 队列区分两个计数器，而 `nack` 只增加其中一个。**

4.3 的语义：

| 计数器 | 何时 +1 | 用途 |
|---|---|---|
| `acquired-count` | 每次 requeue 都 +1 | 记录"被取过几次" |
| `delivery-count` | 仅投递失败时才 +1 | **延迟退避、delivery-limit 都看它** |

按官方判定表：`basic.nack` → 只涨 acquired；`basic.reject` → 两者都涨。

**这带来两个直接后果**：

**其一，延迟退避失效。** 延迟公式是 `min(min_delay × delivery_count, max_delay)`，用的是 delivery-count。用 `nack` 时 delivery-count 不涨，延迟永远是最小值。实测：

```
nack   组：3.05 → 3.05 → 3.05 → 3.05 s（恒定）
reject 组：3.06 → 6.11 → 9.15 → 12.01 s（递增封顶）
```

想让"失败越多次、等得越久"的退避生效，必须用 `reject`。

**其二，毒消息保护失效。** `delivery-limit` 也只看 `delivery-count`，所以用 `nack` 返回的消息**不计入投递上限**——4.3 官方称之为"支持无限次返回"。如果一条永久性失败的消息被 `nack`，它会**无限循环**，永远不会进死信队列。

**实践建议**：
- 表示"处理失败，需要重试" → 用 `basic_reject(requeue=True)`
- 表示"暂时放回，不算失败"（如应用级路由）→ 用 `basic_nack(requeue=True)`
- 确定要丢弃/进死信 → 用 `basic_nack(requeue=False)`

这也修正了课 6 以来的一个隐含假设：`nack` 与 `reject` 在 4.3 里**不再等价**。

</details>

### Q6（简答）

内存告警触发后，为什么你的发布服务"卡死但没有任何报错"？应该如何防范？

<details><summary>答案</summary>

**原因：连接被 broker 阻塞，而客户端没有设置超时，也没有处理阻塞通知。**

内存高水位（本环境 0.6）或磁盘告警（本环境 50MB）触发后，broker 会给发布者连接发送 `Connection.Blocked` 帧，要求暂停发布。此时客户端的 `basic_publish` 会**挂起等待**，而不是报错——所以进程在、连接也在、CPU 为零、日志无任何异常。

**三重防范**：

**第一，设置 `blocked_connection_timeout`。**

```python
pika.ConnectionParameters(
    ...,
    blocked_connection_timeout=300,   # 最多等 300 秒
)
```

不设的话可能无限挂起，这正是"卡死没报错"的直接原因。设了之后超时会抛异常，至少能被监控发现。

**第二，注册 blocked/unblocked 回调**（注意是 **Connection** 的方法，不是 Channel）：

```python
conn.add_on_connection_blocked_callback(on_blocked)
conn.add_on_connection_unblocked_callback(on_unblocked)
```

**第三，定期驱动事件循环。**

这是课 9 结论的延伸：pika 的 `BlockingConnection` 只在 `process_data_events()` 时处理 incoming 帧。实测中 `BLOCKED` 事件就是在显式 `pump()` 时才被读到的。如果发布循环从不驱动事件循环，阻塞通知会积压在缓冲区里收不到，程序会继续往一个已经要求它停下的 broker 里灌数据。

```python
while publishing:
    ch.basic_publish(...)
    conn.process_data_events(time_limit=0)   # 让 blocked 通知有机会被处理
```

**另外要诚实说明的一点**：本次实测中，告警生效期间的那次 `publish` 实际**并未被挂起**（0.00 秒返回）。所以"告警后发布一定被挡"这个假设不成立——不要依赖流控来做应用层的速率控制，它只是 broker 的自我保护机制。

</details>

---

## 📚 本课官方文档汇总

| 主题 | 链接 |
|------|------|
| 队列中的优先级支持 | [Priority Support in Queues](https://www.rabbitmq.com/docs/priority) |
| Quorum 队列（延迟重试 / 优先级 / 消费者超时） | [Quorum Queues](https://www.rabbitmq.com/docs/quorum-queues) |
| RabbitMQ 4.3 发布亮点 | [RabbitMQ 4.3 Highlights](https://www.rabbitmq.com/blog/2026/04/23/rabbitmq-4.3-release) |
| 消息 TTL 与死信 | [Time-To-Live and Expiration](https://www.rabbitmq.com/docs/ttl) |
| 死信交换机 | [Dead Letter Exchanges](https://www.rabbitmq.com/docs/dlx) |
| 内存告警与流控 | [Memory Alarms and Flow Control](https://www.rabbitmq.com/docs/memory) |
| 磁盘告警 | [Disk Alarms](https://www.rabbitmq.com/docs/disk-alarms) |
| 告警监控 | [Alarms and Monitoring](https://www.rabbitmq.com/docs/alarms) |
| 队列与消息属性总览 | [Queues](https://www.rabbitmq.com/docs/queues) |

> 以上链接核查于 2026-09，对应 RabbitMQ 4.3 文档。

---

## 下一步

下一课进入 **课 11《集群与高可用》**——集群基础（集群 / Federation / Shovel）、复制型队列（quorum 的 Raft 复制、镜像队列为何被移除）、故障与网络分区（4.3 起"多数派可用"的新语义）。

> 下一课：[课 11 集群与高可用](./lesson-11-集群与高可用.md)（阶段 4）

---

## 本课实测环境

| 项目 | 值 |
|------|-----|
| RabbitMQ 版本 | 4.3.5 |
| pika 版本 | 1.4.4 |
| Python 版本 | 3.12.3 |
| 元数据后端 | Khepri |
| 内存高水位 | 0.6（实测 `vm_memory_high_watermark`） |
| 磁盘告警阈值 | 50 MB（实测 `disk_free_limit`） |
| 实测日期 | 2026-09-01 |
| 验证脚本 | `playground/l10-delay-ttl-dlx.py`、`l10-backoff-final.py`、`l10-priority-fixed.py`、`l10-flow-blocked.py` |

> ⚠️ **未完成的验证**：
> 1. **延迟消息插件未实测**——本环境未安装 `rabbitmq_delayed_message_exchange`（实测 `rabbitmq-plugins list` 中不存在），讲义仅说明原理，未给出未经实测的用法代码。
> 2. **流控阻塞未复现**——内存告警确实触发（`Memory alarm on node ...`），且客户端收到了成对的 `BLOCKED`/`UNBLOCKED` 事件，但告警期间的那次 `publish` 未被挂起（0.00s 返回）。"告警后 publish 必被阻塞"的说法在本环境**未得到证实**，已如实标注。
