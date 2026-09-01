# 第 9 课：Python 客户端工程实践

> 所属阶段：阶段 4《进阶与工程落地》｜ 水平：零基础 ｜ 本课知识点：连接与信道管理、生产者模板、消费者模板
> 故事情节：主角要上岗了——从"能跑通的 demo"到"能在线上扛事的代码"，差的是这些工程细节

## 🎯 本课目标

- 说清 Connection 与 Channel 的关系，配置心跳并实现断线重连
- 写出 confirm + mandatory + persistent 三件套齐备的生产者模板
- 写出手动 ack + prefetch + 失败重试 + 优雅关闭的消费者模板

## 知识点清单（含关键点）

1. **连接与信道管理**（关键点：为什么信道是轻量虚拟连接 / 心跳 heartbeat 与断线检测 / 断线重连 / BlockingConnection 与 SelectConnection 的取舍）
2. **生产者模板**（关键点：confirm + mandatory + persistent 三件套 / basic_return 处理不可路由 / 异常与重发策略 / 连接复用）
3. **消费者模板**（关键点：manual ack + prefetch / 处理失败与有限次重试 / 优雅关闭与信号捕获 / 并发消费模型）

---

## 开场：为什么学了八课还不够

前八课你学会了：消息怎么路由（课 4）、队列有哪些属性（课 5）、怎么确认（课 6）、怎么持久化（课 7）、怎么保证幂等（课 8）。

但有一个尴尬的事实：**这些知识装在 demo 代码里，一上线就会出事。**

来看一个真实的差距。这是课 3 里"能跑通"的生产者：

```python
import pika
conn = pika.BlockingConnection(pika.ConnectionParameters('localhost'))
ch = conn.channel()
ch.basic_publish(exchange='', routing_key='hello', body=b'Hello!')
conn.close()
```

五行代码，消息发出去了。它有什么问题？

- 网络抖一下，连接断了，消息发出去没有？**不知道**（没开 confirm）
- routing key 写错了，消息进了黑洞，**不知道**（没开 mandatory）
- broker 重启，消息还在吗？**不知道**（没设 persistent）
- 服务跑了一周，某天深夜连接悄悄死掉，**没人知道**（心跳是默认的，且没有重连逻辑）

这四个"不知道"，就是本节课要消灭的东西。

> **本课的一句话主旨**：前八课解决"消息能不能正确送达"，本课解决"程序能不能长期稳定地送达"。前者是算法问题，后者是工程问题。

---

## 知识点 1：连接与信道管理

### 第一幕：一个真实的线上故障

清晨 9 点，监控报警：订单队列积压 3 万条。

运维查了一圈：

- RabbitMQ 服务？正常，CPU 12%
- 消费者进程？在跑，`ps` 能看到，CPU 0%
- 消费者日志？最后一行是昨晚 23:47，之后**再无任何输出**
- Management UI 上的连接列表？**这个消费者连接还在**

进程在、连接也在、就是不消费。重启消费者进程，积压瞬间开始下降。

这就是本课要讲的**头号线上事故**：半开连接（half-open connection）。

### 为什么连接会"假活"

TCP 连接有个特点：**如果对方机器突然断电或网络中断，本机不会收到任何通知**。

对端消失了，但本端的 TCP 协议栈还保留着这条连接的所有状态，认为它一切正常。这块"僵尸连接"会一直存在，直到：

- 本机尝试发送数据并且失败（但消费者只在等消息，不发数据）
- 或者 TCP 层超时（Linux 默认约 **11 分钟**，甚至更长）

所以在最坏情况下，消费者会在**十几分钟里完全不知道自己已经"瞎"了**——进程在、连接还在、CPU 为零、消息一条不消费。

AMQP 协议为此设计了**心跳（heartbeat）**机制：哪怕没有任何业务数据，双方也要定期互发一个小帧证明自己还活着。

### 心跳是怎么工作的

先记住两个容易混淆的概念：

| 概念 | 含义 | 关系 |
|------|------|------|
| **心跳超时（timeout）** | 多久没收到对方消息就判定对方死亡 | 配置里填的就是这个 |
| **心跳间隔（interval）** | 每隔多久主动发一个心跳帧 | = timeout ÷ 2 |

判定规则：**连续两次心跳周期没收到任何帧**（任何帧，包括业务数据），就认为连接已死，关闭 TCP 连接。

所以：**感知时延 ≈ 2 × heartbeat**。

### 实测：心跳配置与感知时延

用 `heartbeat=10` 建连接，实测 pika 内部的心跳参数：

```
| 客户端请求 heartbeat | 发送间隔 _send_interval | 协商超时 |
|----------------------|------------------------|----------|
| 0                    | None                   | 0        |
| 15                   | 7.5                    | 15       |
| 30                   | 15.0                   | 30       |
| 60                   | 30.0                   | 60       |
| 120                  | 60.0                   | 120      |
| 600                  | 300.0                  | 600      |
```

（`l9-heartbeat.py`，RabbitMQ 4.3.5 / pika 1.4.4）

三个可直接使用的结论：

第一，**发送间隔确实是超时的一半**（30 → 15.0、600 → 300.0），与规范一致。

第二，**`heartbeat=0` 等于自杀**。看第一行，`_send_interval` 是 `None`——心跳检查器根本没创建。此时断网后要等 TCP 层超时（十几分钟）才会被发现。生产环境**永远不要设 0**。

第三，**服务端默认是 60 秒，这意味着断网后最长要等 120 秒**才发现。这 120 秒里，你的消费者是一条消息都不会处理的。

| heartbeat | 心跳帧间隔 | 断网后最长感知时延 |
|-----------|------------|-------------------|
| 5s | 2.5s | 10s |
| 10s | 5.0s | 20s |
| 20s | 10.0s | 40s |
| 30s | 15.0s | 60s |
| 60s（服务端默认） | 30.0s | **120s** |

官方给出的推荐区间是 **5 ~ 20 秒**：低于 5 秒容易因网络抖动产生误判（把正常连接当成死的），高于 20 秒则故障感知太慢。

### ⚠️ 一个反直觉的发现：心跳值到底谁说了算？

几乎所有中文教程都会告诉你：

> "心跳是客户端和服务端协商的，**取两者的较小值**，所以客户端只能调小、不能调大。"

这句话**对，但只对一部分客户端成立**。

官方文档的原话是，这个"取较小值"算法是 **Java / .NET / Erlang 官方客户端**采用的。而 pika 是社区维护的客户端，它的实现不一样。

直接看 pika 1.4.4 的源码：

```python
@staticmethod
def _tune_heartbeat_timeout(client_value: Optional[int], server_value: int) -> int:
    """Determine heartbeat timeout per AMQP 0-9-1 rules

    If the client specifies a value, it always takes precedence.
    """
    if client_value is None:
        # Accept server's limit
        timeout = server_value
    else:
        timeout = client_value
    return timeout
```

逻辑极其直白：**客户端只要填了值，就无条件优先**，服务端建议值直接被忽略。

实测验证（服务端配置 `heartbeat = 60`，客户端请求 600）：

```
| 连接 | 服务端记录的 timeout |
|------|----------------------|
| 172.17.0.1:55324 -> 172.17.0.2:5672 | 30 |
| 172.17.0.1:55334 -> 172.17.0.2:5672 | 600 |
```

请求 600 的连接，服务端记录的就是 **600**，没有被压成 60。

**这意味着什么？**

如果你按"取较小值"的假设，觉得"反正服务端会兜底、我随便填个大的没事"——**在 pika 上你会得到一个 600 秒的心跳**，也就是断网后要等 20 分钟才发现。

> **一句话记住**：心跳最终值取决于**客户端库的实现**，不同库算法不同（官方客户端取小、pika 客户端优先、旧版 pika 甚至取大）。不要依赖任何"别人会帮我兜底"的假设，**显式配置一个 5~20 秒的值**。

### 第二幕：连接与信道，到底什么关系

现在回答另一个问题：为什么要有 Channel（信道）这个东西？

直接看数据。实测创建 50 个连接 vs 在 1 个连接上开 50 个信道的耗时：

```
| 场景 | 数量 | 总耗时 | 单条平均 |
|------|------|--------|----------|
| A. 建 50 个 Connection | 50 | 225.2 ms | 4.50 ms/个 |
| B. 开 50 个 Channel    | 50 | 26.3 ms  | 0.53 ms/个 |

比值：建连接是开信道的 8.6 倍耗时
```

（`l9-conn-channel.py`，N=50，已预热排除冷启动）

**8.6 倍**的差距。原因是两者的工作量根本不同：

- **建连接**：TCP 三次握手 → AMQP 协议头 → START/START-OK → TUNE/TUNE-OK → OPEN/OPEN-OK → 认证。多轮网络往返。
- **开信道**：客户端本地登记一个编号 + 一次 `channel.open` 往返。

所以信道的本质是**复用一条 TCP 连接的轻量虚拟连接**：

```
一条 TCP 连接（重量级，多轮握手 + 认证）
 ├── Channel 1  → 消费者 A 用
 ├── Channel 2  → 消费者 B 用
 ├── Channel 3  → 生产者用
 └── ...
```

**使用原则**：

- 一个应用（进程）通常**只需要 1 条连接**，在上面按需开多个信道
- 每个**线程**用**独立的信道**——信道**不是线程安全的**，多线程共用一个信道会串帧
- 连接数是有上限的（受 `channel_max` 和文件描述符限制），不要为每条消息建连接

### 第三幕：断线重连怎么写

连接一定会断，问题是你准没准备好。

先看实测。这段代码故意让服务端强制断开连接，然后观察客户端能否自动恢复（`l9-reconnect.py`）：

```python
def consume_loop():
    while not state['should_stop']:
        try:
            conn = get_conn()          # 建连接
            ch = setup(conn)           # 建信道 + 声明队列
            for method, props, body in ch.consume(QUEUE, auto_ack=False,
                                                  inactivity_timeout=1):
                if method is None:
                    continue           # 空闲超时，继续等
                ch.basic_ack(method.delivery_tag)
        except pika.exceptions.AMQPConnectionError as e:
            print("连接断开，2 秒后重连")
            time.sleep(2)              # 退避后重试
```

实测输出：

```
--- 阶段 1：正常消费 ---
[消费者] 消费 #1：正常消息-1
[消费者] 消费 #2：正常消息-2
[消费者] 消费 #3：正常消息-3

--- 阶段 2：服务端强制断开连接 ---
执行：rabbitmqctl close_all_connections
[消费者] ⚠️ 连接断开：ConnectionClosedByBroker
[消费者] 2 秒后重连（第 1 次）...
[消费者] 连接已建立并开始消费

--- 阶段 3：断线后继续发消息，看能否被消费 ---
[消费者] 消费 #4：断线后消息-1
[消费者] 消费 #5：断线后消息-2
[消费者] 消费 #6：断线后消息-3

重连次数：1
累计消费：6 条
✅ 自动重连成功
```

重连成功，后续消息全部正常消费。

**但必须诚实说明这次实验的局限**：

`rabbitmqctl close_all_connections` 属于**优雅断开**——服务端会主动发一个 `Connection.Close` 帧，客户端是在**收到明确通知**的情况下知道连接断了的，所以是瞬间感知。

而开篇那个线上故障是**半开连接**：收不到任何帧，只能干等心跳超时。这两种情况的**感知时延天差地别**（前者瞬间，后者 2×heartbeat），这是本课最需要记住的区别。

> ⚠️ **实验降级说明**：本课原计划用 `iptables DROP` 在容器内制造真实的半开连接并测量感知时延，但实测发现**容器内无 iptables**（`command -v iptables` 返回 `NO_IPTABLES`），无法执行。因此上表中的感知时延为**按协议规则推算的理论值**，非本机实测。这个限制如实记录在此，不编造数据。

### 重连代码的四个要点

对照上面的实测代码，一个能用的重连逻辑要注意：

1. **整个连接+信道的建立都要在循环里**。连接断了，信道也一起失效，不能只重建信道。
2. **捕获的是 `AMQPConnectionError`**。它是 pika 连接类异常的父类，`ConnectionClosedByBroker`、`StreamLostError` 等都继承自它。
3. **要有退避**，不要疯狂重试把 broker 打垮。实测代码用了固定 2 秒，生产上建议指数退避 + 抖动。
4. **重连后要重新声明队列和重新 `basic_consume`**。broker 不会记得你之前消费的是哪个队列。

### BlockingConnection 还是 SelectConnection

pika 提供两套适配器，选错会很痛苦：

| | BlockingConnection | SelectConnection |
|---|---|---|
| 编程模型 | 同步阻塞，像普通函数 | 异步回调 + 事件循环 |
| 上手难度 | 低，适合入门 | 高，要理解回调链 |
| 心跳 | 在 `process_data_events` 中自动驱动 | 事件循环驱动 |
| **致命弱点** | **业务回调阻塞时心跳发不出去** | 无此问题 |
| 适合场景 | 脚本、批处理、低吞吐消费者 | 高并发、长连接生产服务 |

**`BlockingConnection` 的致命弱点要说清楚**：

心跳是靠 pika 的事件循环发出去的。如果你的消费回调里有耗时操作（比如调外部 HTTP 接口卡住 60 秒），这 60 秒里 pika 根本没机会发心跳帧——**broker 会认为你死了，主动断开连接**。

这就是为什么课 8 讲"回调里不要做重活"，不只是性能问题，**是生存问题**。

> **选型建议**：学习阶段和简单脚本用 `BlockingConnection`；生产上如果消费逻辑有耗时 I/O，要么在回调里只做"取消息 + 扔进线程池"，要么直接上 `SelectConnection`。
>
> ⏳ 说明：本课 `SelectConnection` 的异步示例在本机未能跑通（课 6 已记录 ioloop 卡住的问题），因此讲义不给出未经实测的异步代码。

---

## 知识点 2：生产者模板

### 第四幕：消息发出去了，然后呢

回到开篇那个五行生产者。它最大的问题是：**发完就不管了**。

`basic_publish` 成功返回，只代表"数据写进了本地 socket 缓冲区"，**不代表 broker 收到了**，更不代表消息进了队列。

生产级生产者需要**三件套**：

| 机制 | 防的是什么 | 缺了会怎样 |
|---|---|---|
| **confirm（发布确认）** | 消息没到达 broker | 发出去就丢了，无人知晓 |
| **mandatory + 退回处理** | 消息到了 broker 但没进任何队列 | 静默进黑洞 |
| **persistent（delivery_mode=2）** | 消息进了队列但 broker 重启后丢失 | 重启即丢 |

注意这三件套**各管一段，不能互相替代**。开了 confirm 不代表消息会持久化，设了 persistent 不代表消息一定路由成功。

### 实测：三件套的效果

`l9-producer-template.py` 的实测结果。

**场景 A：三件套齐全 + 正常路由**

```
publish 未抛异常：True
触发退回的消息数：0（应为 0）
队列 l9.prod.ok 深度：1（应为 1）
```

**场景 B：三件套齐全 + 路由不到**

```
抛出的异常：UnroutableError
退回回调收到的消息：1 条
  reply_code=312  reply_text=NO_ROUTE  body=B-unroutable-msg
```

关键点：如果**不开 mandatory**，这条消息会被 broker **静默丢弃**，发布方拿不到任何提示，消息就这么消失了。开了 mandatory，broker 会把消息退回来，你才能发现"我写错 routing key 了"。

### ⚠️ 实测踩坑：return 回调不触发的两层原因

这是本课最容易踩的坑，分两层，我们一层层剥。

**第一层：不驱动事件循环，回调永远不触发。**

很多同学照着教程注册了回调，结果收不到任何退回消息，以为 mandatory 没生效：

```python
ch.add_on_return_callback(my_callback)
ch.basic_publish(..., mandatory=True)
# 回调没触发？
```

原因：pika 的 `BlockingConnection` 不会在 `basic_publish` 返回时立即处理 incoming 帧。课 4 当时记录的是"补一次同步调用即可"，但本次实测发现**这个说法不够准确**：

```python
ch.queue_declare(queue=..., passive=True)   # 补交互 —— 实测仍然收不到
c.process_data_events(time_limit=0.3)       # 必须显式驱动 —— 这个才行
```

实测对比（同样的 publish + 退回场景）：

| 驱动方式 | 回调是否触发 |
|---|---|
| `queue_declare(passive=True)` 补交互 | ❌ 收不到 |
| `connection.process_data_events()` | ✅ 收到 |

**正确写法**：publish 之后显式调用 `connection.process_data_events()` 驱动事件循环。

**第二层：开了 confirm 之后，还会额外抛异常。**

这是更隐蔽的一层。实测对比：

```
只开 mandatory          异常=None              回调=[(312, 'x')]
mandatory + confirm     异常=UnroutableError   回调=[(312, 'x')]
```

两条通路**都在工作**——回调能收到退回消息（含 `reply_code=312` 和消息体），但**开了 confirm 之后 pika 还会额外抛 `UnroutableError`**。

这个差异的实际影响：如果你只写 `try/except UnroutableError` 而**不驱动事件循环**，你只知道"路由失败"，却**拿不到退回的消息体和具体原因**。反过来，如果你只注册回调却没捕获异常，程序会直接崩。

> **一句话记住**：`mandatory` 的退回消息要走**事件循环**才拿得到；开了 confirm 后它是"**异常 + 回调**"双路通知，两条都要处理。

### confirm 的性能代价

三件套不是免费的。实测 100 条持久化消息：

```
| 模式 | 100 条耗时 | 单条平均 |
|------|-----------|----------|
| 不开 confirm | 2.3 ms | 0.023 ms |
| 开启 confirm | 55.5 ms | 0.555 ms |

倍率：confirm 约为无确认的 24.1 倍耗时
```

24 倍的代价看起来很吓人，但要注意背景：

这呼应课 6 的结论——**pika 的 confirm 是"假异步"**。`BlockingChannel.basic_publish` 在 confirm 模式下会执行 `_flush_output(..., is_ready)`，**逐条同步等待** broker 的 ack。慢的是**同步适配器的用法**，不是 confirm 协议本身。

如果需要高吞吐，正确做法不是关掉 confirm，而是：

- 用批量 confirm（发一批再统一等）
- 或改用 `SelectConnection` 真正异步地发

> **绝不推荐**为了性能关掉 confirm。那等于用"消息可能丢"换"快 24 倍"。

### 生产者模板（可直接复用）

综合以上实测，这是本课给出的生产者模板：

```python
import pika

def make_connection():
    """建连接：显式心跳 + blocked 超时"""
    return pika.BlockingConnection(pika.ConnectionParameters(
        host='localhost', port=5672,
        credentials=pika.PlainCredentials('learn', 'learn123'),
        heartbeat=15,                      # ① 显式心跳 5~20s，别用默认 60
        blocked_connection_timeout=300,    # ② 流控时最多等 300s
    ))


class Producer:
    def __init__(self):
        self.conn = make_connection()
        self.ch = self.conn.channel()
        self.ch.confirm_delivery()                    # ③ 三件套之一
        self.unroutable = []
        self.ch.add_on_return_callback(self._on_return)

    def _on_return(self, ch, method, props, body):
        """④ 三件套之二：接住不可路由的消息"""
        self.unroutable.append({
            'code': method.reply_code,
            'text': method.reply_text,
            'body': body,
        })

    def publish(self, routing_key, body):
        try:
            self.ch.basic_publish(
                exchange='', routing_key=routing_key, body=body,
                properties=pika.BasicProperties(
                    delivery_mode=2,      # ⑤ 三件套之三：持久化
                ),
                mandatory=True,
            )
            return True
        except pika.exceptions.UnroutableError:
            # confirm 模式下的额外异常通路
            return False
        finally:
            # ⑥ 关键：驱动事件循环，否则 _on_return 不触发
            self.conn.process_data_events(time_limit=0)

    def close(self):
        self.conn.close()
```

六处标注就是六个要点，缺一个都可能出事。

---

## 知识点 3：消费者模板

### 第五幕：消费失败怎么办

消费者比生产者复杂，因为要处理**业务失败**。

课 8 已经证明：手动 ack 是零丢失的前提。但"不 ack"之后呢？消息会一直重投，如果这条消息的失败是**永久性的**（比如消息格式非法），它就会**无限循环**——这是课 6 已经警告过的死循环。

正确的做法是**有限次重试 + 最终进死信**：

| 重试次数 | 处理方式 |
|---|---|
| 第 1~N 次失败 | 重新入队，稍后重试 |
| 超过 N 次 | `nack(requeue=False)` → 进死信队列，人工介入 |

### ⚠️ 重试计数不能靠 x-death

课 6 已经用实测证明了一个反直觉的事实：**`nack(requeue=True)` 根本不写 `x-death` 头**，连续三次 requeue，headers 始终是 `{}`。

所以不能用 `x-death` 给 requeue 重试计数——计数恒为 0，恰好造出无限重试死循环。

正确做法是**自己在消息头里维护计数**：

```python
def get_retry_count(headers):
    return int((headers or {}).get('x-retry-count', 0))

headers = dict(props.headers or {})
headers['x-retry-count'] = retry + 1
```

### 优雅关闭：为什么必须捕获信号

消费者进程被 kill 时，如果消息处理到一半，会留下**未 ack 的消息**。这些消息要等 prefetch 超时或连接断开才回到队列，造成消费延迟。

正确做法是捕获 `SIGTERM`（`docker stop` / `kubectl` 默认发的就是它），**当前消息处理完再退出**：

```python
import signal

stopping = False

def on_sigterm(signum, frame):
    global stopping
    print("收到退出信号，当前消息处理完后停止")
    stopping = True

signal.signal(signal.SIGTERM, on_sigterm)
signal.signal(signal.SIGINT, on_sigterm)
```

配合主循环里的 `if stopping: break`，就能做到"不丢消息、不留脏 ack"。

### 消费者模板（可直接复用）

```python
import signal
import time
import pika

MAX_RETRY = 3

class Consumer:
    def __init__(self, queue):
        self.queue = queue
        self.stopping = False
        signal.signal(signal.SIGTERM, self._on_stop)
        signal.signal(signal.SIGINT, self._on_stop)

    def _on_stop(self, signum, frame):
        self.stopping = True

    def connect(self):
        self.conn = pika.BlockingConnection(pika.ConnectionParameters(
            host='localhost', port=5672,
            credentials=pika.PlainCredentials('learn', 'learn123'),
            heartbeat=15, blocked_connection_timeout=300))
        self.ch = self.conn.channel()
        self.ch.basic_qos(prefetch_count=1)      # ① 手动 ack 必须配 prefetch
        self.ch.queue_declare(queue=self.queue, durable=True)

    def run(self):
        while not self.stopping:
            try:
                if not hasattr(self, 'conn') or self.conn.is_closed:
                    self.connect()               # ② 断线重连
                for method, props, body in self.ch.consume(
                        self.queue, auto_ack=False, inactivity_timeout=1):
                    if self.stopping:
                        break
                    if method is None:
                        continue
                    self.handle(method, props, body)
            except pika.exceptions.AMQPConnectionError as e:
                print("连接断开，2 秒后重连")
                time.sleep(2)
        self.shutdown()

    def handle(self, method, props, body):
        retry = int((props.headers or {}).get('x-retry-count', 0))
        try:
            do_business(body)                    # 你的业务逻辑
            self.ch.basic_ack(method.delivery_tag)   # ③ 手动 ack
        except Exception as e:
            if retry >= MAX_RETRY:
                # ④ 超过上限：进死信，不再重投
                self.ch.basic_nack(method.delivery_tag, requeue=False)
            else:
                # ⑤ 有限次重试：自维护计数后重发
                self.ch.basic_ack(method.delivery_tag)
                headers = dict(props.headers or {})
                headers['x-retry-count'] = retry + 1
                self.ch.basic_publish(
                    exchange='', routing_key=self.queue, body=body,
                    properties=pika.BasicProperties(
                        delivery_mode=2, headers=headers))

    def shutdown(self):
        """⑥ 优雅关闭：停止消费 + 关闭连接"""
        try:
            self.ch.cancel()
            self.conn.close()
        except Exception:
            pass
```

六个要点：

1. **`prefetch_count=1`**——课 6 已证，没有 prefetch 会让一个消费者抢空整个队列
2. **连接失效时整体重建**——信道跟着连接一起失效
3. **手动 ack**——课 8 已证，auto_ack 崩溃会丢光整个队列
4. **超过重试上限进死信**——`requeue=False` 才会触发死信（课 7 已证）
5. **自维护重试计数**——`x-death` 在 requeue 时不写（课 6 P0 实测）
6. **优雅关闭**——先 `cancel()` 停止拉取，再 `close()`

### 并发消费模型

消费者的并发有三种层次，选错会踩大坑：

| 方案 | 做法 | 优点 | 坑 |
|---|---|---|---|
| **多进程**（推荐） | 起 N 个消费者进程 | 隔离性好，一个崩不影响其他 | 进程数 = 连接数 |
| **多线程 + 多信道** | 1 连接，每线程独立信道 | 省连接 | 回调耗时会阻塞心跳 |
| **多线程 + 单信道** | ❌ 错误做法 | - | **信道非线程安全，会串帧** |

**为什么多进程优于多线程**，课 8 有一个非常有说服力的实测：pika 多线程测出"4 个消费者吞吐比 1 个还低（慢 13 倍）"。原因是 GIL 限制——Python 多线程无法真正并行，而 pika 的 `BlockingConnection` 受 GIL 拖累。改用多进程绕开 GIL 后，吞吐立刻正常。

所以：

> **一条铁律**：pika 的多线程消费几乎总是错的。要并发，用**多进程**，每个进程一条独立连接。

### ⚠️ 一个真实踩到的并发陷阱

本课做半开连接实验时，真实撞到一个 pika 的并发陷阱，值得记录：

主线程持有一个连接，同时另起一个线程在这条连接的信道上 `consume()`；当主线程调用 `conn.close()` 时，抛出了：

```
pika.exceptions.StreamLostError: Stream connection lost:
    IndexError('pop from an empty deque')
```

原因：`close()` 内部会调用 `_cancel_all_consumers()` 尝试优雅取消消费者，而此时信道正被另一个线程用于消费，两边争用同一个输出队列，导致内部状态损坏。

**教训**：**一条连接/信道不要跨线程同时使用**。如果确实要并发，每个线程开自己的信道；关闭时先让消费线程退出，再关连接。

---

## 本课要点速查卡

| 主题 | 结论 |
|---|---|
| 连接 vs 信道 | 建连接比开信道贵 **8.6 倍**（4.50ms vs 0.53ms，N=50） |
| 信道线程安全 | ❌ 非线程安全，多线程必须各用各的信道 |
| 心跳推荐值 | **5 ~ 20 秒**；服务端默认 60s = 断网后最长 **120s** 才感知 |
| 心跳协商 | 取决于客户端库：官方客户端取小、**pika 客户端值优先** |
| heartbeat=0 | 生产禁止，等于放弃故障检测 |
| 半开连接 | 收不到任何帧，只能靠心跳超时发现（2×heartbeat） |
| 重连要点 | 连接+信道一起重建、捕获 `AMQPConnectionError`、退避重试 |
| 生产者三件套 | confirm + mandatory + persistent，**各管一段不可替代** |
| return 回调 | 必须 `process_data_events()` 驱动才触发 |
| confirm + mandatory | **异常 + 回调**双路通知，两条都要处理 |
| confirm 代价 | 约 **24 倍**耗时（100 条：2.3ms → 55.5ms），因 pika 逐条同步等 |
| 消费者三件套 | 手动 ack + prefetch + 有限重试 |
| 重试计数 | **不能靠 x-death**（requeue 不写），自维护 `x-retry-count` |
| 并发模型 | 用**多进程**，不要多线程（GIL + 信道非线程安全） |
| 优雅关闭 | 捕获 SIGTERM，处理完当前消息再退出 |
| 跨线程关连接 | 会抛 `StreamLostError`，先停消费线程再关 |

---

## 常见误区

| # | 误区 | 真相 |
|---|------|------|
| 1 | "连接断了客户端会立刻知道" | 半开连接收不到任何帧，要等 **2×heartbeat** |
| 2 | "心跳取客户端和服务端的较小值" | 那是**官方客户端**的算法；**pika 是客户端值优先** |
| 3 | "心跳用默认的就行" | 默认 60s，断网后最长 120s 才发现，太慢 |
| 4 | "为了性能可以关掉 confirm" | 用"可能丢消息"换 24 倍吞吐，不可接受 |
| 5 | "注册了 return 回调就能收到退回" | 必须 `process_data_events()` 驱动事件循环 |
| 6 | "confirm 模式下捕获异常就够了" | 还要驱动事件循环才能拿到退回的消息体 |
| 7 | "信道可以多线程共用" | ❌ 非线程安全，会串帧 |
| 8 | "用 x-death 给重试计数" | requeue=True **不写** x-death，计数恒为 0 → 死循环 |
| 9 | "重试次数不设上限比较保险" | 永久性失败会无限循环，必须有上限后进死信 |
| 10 | "开了 persistent 就等于消息不会丢" | 课 7 已证：classic 队列 confirm 前**不 fsync**，存在丢失窗口 |

---

## 🧪 小测

### Q1（单选）

你的消费者进程在、连接也在，但消息一条都不消费。最可能的原因是什么？

A 队列里其实没有消息
B broker 流控把消费者阻塞了
C 半开连接：进程不知连接已死，只能靠心跳超时发现
D 消费者 prefetch 设置过大

<details><summary>答案</summary>

**C**。

这正是本课开篇的线上故障。TCP 连接在对端突然消失时不会通知本机，形成"半开连接"——进程在、连接状态也在，但数据永远收不到。只能靠心跳超时（2×heartbeat）发现。

A 错：如果有积压，队列里当然有消息。
B 错：流控是真实机制，但它影响的是**发布者**，且会有明确告警。
D 错：prefetch 过大影响的是分发公平性，不会导致完全不消费。

</details>

### Q2（单选）

关于心跳协商，下列说法正确的是？

A 一定取客户端和服务端配置的较小值
B 客户端配置的值永远优先
C 取决于客户端库的实现，pika 是客户端值优先
D 由服务端单方面决定，客户端配置无效

<details><summary>答案</summary>

**C**。

官方文档说的"取较小值"针对的是 **Java/.NET/Erlang 官方客户端**。pika 1.4.4 的 `_tune_heartbeat_timeout` 源码是 `if client_value is None: server_value else: client_value`，即**客户端填了就无条件优先**。实测服务端 60、客户端请求 600，结果就是 600。

A 错：只对官方客户端成立。
B 错：表述太绝对，且客户端填 `None` 时会接受服务端值。
D 错：服务端值在客户端未指定时才生效。

</details>

### Q3（多选）

生产者"三件套"各自防的是什么？（多选）

A confirm 防消息没到达 broker
B mandatory 防消息没进任何队列
C persistent 防 broker 重启后消息丢失
D confirm 能保证消息已落盘

<details><summary>答案</summary>

**A、B、C**。

三件套各管一段，不能互相替代。

D 错：这是最容易混淆的一点。课 7 已实测证明，**classic 队列在发送 confirm 之前不执行 fsync**，官方原文是"even durable messages that a publisher received a confirmation for, can technically be lost if the server crashes"。需要强保证要用 quorum 队列。

</details>

### Q4（单选）

你注册了 `add_on_return_callback`，但 mandatory 的退回消息始终收不到。最可能的原因是？

A mandatory 参数没生效
B 没有调用 `process_data_events()` 驱动事件循环
C 必须同时开启 confirm
D 必须用 SelectConnection 才能收到

<details><summary>答案</summary>

**B**。

pika 的 `BlockingConnection` 不会在 `basic_publish` 返回时自动处理 incoming 帧。本次实测发现，课 4 记录的"补一次同步调用即可"**并不够**——用 `queue_declare(passive=True)` 补交互仍然收不到，必须显式调用 `connection.process_data_events()`。

A 错：mandatory 本身生效了（场景 B 确实收到了 312 退回）。
C 错：不开 confirm 也能收到退回（本课实测"只开 mandatory"就收到了）。
D 错：BlockingConnection 可以，只是要驱动事件循环。

</details>

### Q5（简答）

为什么推荐用多进程而不是多线程来做并发消费？请给出两个理由。

<details><summary>答案</summary>

**理由一：GIL 限制。**

课 8 实测：pika 多线程测出"4 消费者 1986 条/秒 < 1 消费者 27217 条/秒"（慢 13 倍），与常识完全相反。改用多进程绕开 GIL 后，1/2/4 进程吞吐几乎相同且**各进程消息数均分**，证明并发分发确实生效。Python 多线程无法真正并行计算，pika 的 `BlockingConnection` 受此拖累。

**理由二：信道不是线程安全的。**

多线程必须每个线程用独立信道。而如果共用信道，帧会按信道号交织导致响应对不上号（课 2 已讲机制）。本课还实测撞到一个真实陷阱：一条连接/信道跨线程同时使用（一个线程 consume、另一个线程 close），会抛出 `StreamLostError: IndexError('pop from an empty deque')`。

**补充**：多进程还有隔离性优势——一个进程崩溃不影响其他进程。

</details>

### Q6（简答）

你的消费者需要对失败消息做重试，并且重试 3 次后进死信。有同学建议用 `x-death` 头里的 `count` 字段做计数。这个方案可行吗？为什么？应该怎么做？

<details><summary>答案</summary>

**不可行。**

课 6 已用实测证明：**`nack(requeue=True)` 完全不写 `x-death`**——连续三次 requeue，headers 始终是 `{}`，`x-death` 为 `None`。用它计数，count 恒为 0，永远达不到 3，**恰好造出无限重试死循环**。

`x-death` 只在消息被**死信化**时才产生（requeue=False / TTL 过期 / 超 max-length）。

**正确做法**：自己维护计数。

```python
retry = int((props.headers or {}).get('x-retry-count', 0))
if retry >= MAX_RETRY:
    ch.basic_nack(method.delivery_tag, requeue=False)   # 进死信
else:
    ch.basic_ack(method.delivery_tag)
    headers = dict(props.headers or {})
    headers['x-retry-count'] = retry + 1
    ch.basic_publish(exchange='', routing_key=queue, body=body,
                     properties=pika.BasicProperties(
                         delivery_mode=2, headers=headers))
```

注意：重试走的是"ack + 重发"而不是"nack + requeue"，因为 requeue 在队列有积压时会把消息挤到队尾、破坏顺序（课 8 F5 已证）。

</details>

---

## 📚 本课官方文档汇总

| 主题 | 链接 |
|------|------|
| 心跳与 TCP Keepalive | [Detecting Dead TCP Connections with Heartbeats](https://www.rabbitmq.com/docs/heartbeats) |
| 连接与信道 | [Connections and Channels](https://www.rabbitmq.com/docs/connections) |
| 可配置限制（heartbeat/channel_max 等） | [Configurable Limits](https://www.rabbitmq.com/docs/limits) |
| 配置项说明（heartbeat 默认 60） | [Configuration](https://www.rabbitmq.com/docs/configure) |
| 发布者确认 | [Publisher Confirms](https://www.rabbitmq.com/docs/confirms) |
| 消费者确认与预取 | [Consumer Acknowledgements and Publisher Confirms](https://www.rabbitmq.com/docs/confirms) |
| 消费者预取 | [Consumer Prefetch](https://www.rabbitmq.com/docs/consumer-prefetch) |
| 可靠性总纲 | [Reliability Guide](https://www.rabbitmq.com/docs/reliability) |
| pika 文档 | [pika.readthedocs.io](https://pika.readthedocs.io/) |

> 以上链接核查于 2026-09，对应 RabbitMQ 4.3 文档。

---

## 下一步

下一课进入 **课 10《高级特性》**——延迟消息与延迟重试、优先级队列、流控与资源水位。

> 下一课：[课 10 高级特性](./lesson-10-高级特性.md)（阶段 4）

---

## 本课实测环境

| 项目 | 值 |
|------|-----|
| RabbitMQ 版本 | 4.3.5 |
| pika 版本 | 1.4.4 |
| Python 版本 | 3.12.3 |
| 元数据后端 | Khepri |
| 实测日期 | 2026-09-01 |
| 验证脚本 | `playground/l9-heartbeat.py`、`l9-conn-channel.py`、`l9-reconnect.py`、`l9-producer-template.py` |

> ⚠️ **未完成的验证**：半开连接的真实感知时延未能实测（容器内无 iptables），表中数值为按协议规则推算的理论值。相关限制已在知识点 1 中如实标注。
