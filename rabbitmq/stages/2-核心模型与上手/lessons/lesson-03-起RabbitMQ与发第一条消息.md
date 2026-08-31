# 第 3 课：起 RabbitMQ 与发第一条消息

> 所属阶段：阶段 2《核心模型与动手上手》｜ 水平：零基础 ｜ 本课知识点：Docker 起服务与端口、Management UI 巡礼、Python 发第一条消息、CLI 常用命令
> 故事情节：主角第一次真正上路——把 RabbitMQ 跑起来，亲手把一条消息从 Python 送进去再取出来
> 版本口径：RabbitMQ 4.3.x（核查于 2026-08）｜ **本课所有命令与输出均在本机实测运行过**（RabbitMQ 4.3.5 + pika 1.4.4 + Python 3.12）

## 🎯 本课目标

- 一条命令用 Docker 起 RabbitMQ，说清 5672 与 15672 两个端口的作用
- 在 Management UI 中观察队列、交换机与绑定，并手动发布一条测试消息
- 写出 pika 的最小收发程序并跑通
- 用 rabbitmqctl / rabbitmqadmin / rabbitmq-diagnostics 查看队列、交换机、绑定与节点状态

> ⚠️ **本课是本课程第一个真正的动手课，也是最容易卡住的一课。** 网上 90% 的 RabbitMQ 入门教程（包括官方教程的部分示例）在 4.x 上**跑不通**，会在声明队列那一步直接报错。本课会先把这个坑讲清楚再往下走——**这不是你的错，是版本变了**。

---

## 第一幕：起源与场景引入

前两课我们把道理讲完了：同步调用会撞墙，消息队列能解耦、削峰、异步、可靠，而 RabbitMQ 是 AMQP 协议最著名的开源实现，用 Erlang 写成，主打灵活的路由能力。

但到目前为止，**你还没有真正跑过一次 RabbitMQ**。

这就像学完了汽车原理却没摸过方向盘。你脑子里有交换机、队列、绑定、信道这些名词，但它们还只是名词——你不知道它们长什么样，不知道消息发进去之后去了哪里，也不知道怎么确认「确实发成功了」。

今天我们要做的，是把它**跑起来**，然后亲手送一条消息进去，再亲手把它取出来。

> 🎬 **场景**：道理都懂了，但服务还没起、消息还没发——今天就让主角第一次真正上路。

---

## 第二幕：认知冲突

你兴致勃勃地打开官方教程，照着写下人生第一个 RabbitMQ 程序：

```python
channel.queue_declare(queue='hello')
```

然后，报错了：

```
pika.exceptions.ConnectionClosedByBroker: (541, 'INTERNAL_ERROR - Feature `transient_nonexcl_queues` is deprecated.
By default, this feature is not permitted anymore. ...')
```

**连接被 broker 直接掐断。** 你还没发消息，就先被请出去了。

你检查了端口、账号、密码、Docker 映射，全都是对的。你甚至怀疑是不是镜像坏了，重新拉了一遍，还是一样。去搜这个报错，发现 2026 年不少人踩了同一个坑——连 **Debian 的官方打包测试、Apache Camel 的集成组件**都被它搞挂了。

再往下翻，发现第二个坑：好不容易改成 `durable=True` 跑通了，又冒出一个新错：

```
pika.exceptions.ChannelClosedByBroker: (406, "PRECONDITION_FAILED - inequivalent arg 'durable'
for queue 'hello' in vhost '/': received 'false' but current is 'true'")
```

**已经在 broker 里的队列，属性改不了，只能删掉重建。**

> ❓ **问题**：为什么一个"声明队列"这么基础的操作，会同时踩两个坑？**队列的 durability（持久性）到底是个什么属性，为什么 RabbitMQ 4.x 要把它管得这么严？**

---

## 第三幕：层层揭示

> 🧭 **本课会踩 4 个坑，先给你地图**（都是我实测复现过的，不是吓唬你）：
>
> | # | 坑 | 出现在 | 一句话解法 |
> |---|-----|--------|-----------|
> | 1 | 4.3 默认禁止非持久化非排他队列 | 知识点 3 | `queue_declare(durable=True)` |
> | 2 | 队列属性创建后不可改 | 知识点 3 | `rabbitmqctl delete_queue` 重建 |
> | 3 | `rabbitmqadmin` 新版语法变了 | 知识点 4 | 去掉列名参数 |
> | 4 | 设了自定义账号后 guest 消失 | 知识点 1 | 用自定义账号登录 |
>
> **前两个是"代码跑不起来"级别的坑，卡住就往下读，知识点 3 有完整报错原文和解法。**

### 知识点 1：Docker 起服务与端口

> 本知识点关键点：镜像标签选择 / 5672 与 15672 / 默认 guest 的真实限制（Docker 镜像是例外）/ 数据持久化挂载

#### 一句话定义

用官方镜像一条 `docker run` 起一个单节点 RabbitMQ，核心是**映射对端口**——`5672` 是程序收发消息的 AMQP 端口，`15672` 是给人看的管理界面端口。

#### 直觉建立（类比）

**把 RabbitMQ 想成一栋邮局。**

- `5672` = **邮局的业务窗口**：寄件人（生产者）和收件人（消费者）走这里，递包裹、收包裹，全是机器对机器的对话。
- `15672` = **邮局的监控大屏**：局长（你）在这里看今天收了多少件、哪些格子满了、有没有积压。人不走业务窗口办业务，大屏也不负责递包裹。

**这两个口子职责完全不同，混用是初学者最常见的第一个错误**——把代码里的 `port` 写成 `15672`，程序会连上却立刻被掐断，因为大屏不收包裹。

#### 核心原理

**① 镜像标签怎么选**

```bash
docker pull rabbitmq:4.3-management
```

标签有讲究：

| 标签 | 含管理界面？ | 适用 |
|------|-------------|------|
| `rabbitmq:4.3` | ❌ 不含 | 生产环境（少一层攻击面） |
| `rabbitmq:4.3-management` | ✅ 含 | **学习/开发，就用这个** |
| `rabbitmq:latest` | ❌ 不含 | 不推荐，版本漂移会坑你 |

> 💡 **为什么学习必须用 `-management`**：没有它，你就没有 Management UI 和 HTTP API——**看不见 broker 内部发生了什么**，学路由的时候会非常痛苦。

**② 端口全表（核查于 2026-08，官方 networking 文档）**

| 端口 | 用途 | 你要记吗 |
|------|------|----------|
| **5672** | AMQP 0-9-1 / 1.0 明文协议 | ✅ **必须记** |
| **15672** | Management UI + HTTP API | ✅ **必须记** |
| 15671 | Management UI 的 HTTPS | 生产用 |
| 5671 | AMQPS（AMQP over TLS） | 生产用 |
| 25672 | Erlang 分布式 / 节点间通信 | 集群用（课 11） |
| 15692 | Prometheus 监控指标 | 监控用 |
| 5552 / 5551 | Stream 协议明文 / TLS | 流队列用 |
| 4369 | epmd 节点发现 | 集群用 |

**本课只用得到前两个。**

**③ 启动命令**

```bash
docker run -d --name rabbitmq-learn \
  -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=learn \
  -e RABBITMQ_DEFAULT_PASS=learn123 \
  rabbitmq:4.3-management
```

逐段解释：

| 参数 | 作用 |
|------|------|
| `-d` | 后台运行 |
| `--name rabbitmq-learn` | 起个名字，后面所有命令都用它，别用随机名 |
| `-p 5672:5672` | 把容器的 5672 映射到宿主机的 5672（`-p 宿主机:容器`） |
| `-e RABBITMQ_DEFAULT_USER/PASS` | **创建自定义管理员账号**，覆盖默认的 guest |

**启动要等 20–40 秒**，不是立刻可用。用这条命令等它就绪：

```bash
docker logs -f rabbitmq-learn
```

看到这一行才算真的起来了：

```
Server startup complete; 4 plugins started.
```

> 💡 **别用 `docker ps` 判断就绪**——容器 "Up" 只代表进程起来了，不代表 RabbitMQ 完成初始化。

**④ 默认账号 guest 的真实规则（实测，核查于 2026-08）**

教科书上说"**guest/guest 只能在 localhost 登录**"。但**官方 Docker 镜像是个例外**，我实测确认了这一点——这里有个几乎所有教程都写错的地方。

我用干净容器做了对照实验（脚本在 `playground/diag4.sh`、`diag5.sh`、`diag6.sh`）：

**实验 A：不设自定义用户，起干净容器**

```bash
docker exec rabbitmq-probe rabbitmqctl list_users
# user    tags
# guest   [administrator]
```

查它的实际配置：

```bash
docker exec rabbitmq-probe rabbitmqctl environment | grep loopback
#       {loopback_users,[]},          ← 空列表！没有任何用户被限制为本机
```

**为什么会这样？** 我找到了镜像内置的配置文件 `/etc/rabbitmq/conf.d/10-defaults.conf`，开头就写着：

```ini
## DEFAULT SETTINGS ARE NOT MEANT TO BE TAKEN STRAIGHT INTO PRODUCTION
## allow access to the guest user from anywhere on the network
loopback_users.guest = false
```

**镜像显式放开了 guest 的 loopback 限制**，并且自己标注了"默认设置不应当直接用于生产"。

**实验 B：从容器外部（WSL，经端口映射）用 guest 连接**

```bash
# 连 5673（映射到容器的 5672）
# OK: guest 从 WSL 可以连上 5673

curl -s -u guest:guest http://localhost:15673/api/whoami
# {"name":"guest","tags":["administrator"],"is_internal_user":true}
```

**都能连上。** 也就是说：**在官方 Docker 镜像里，用默认的 guest/guest 从任何地方都能登录。**

> ⚠️ **这个"教科书说法"到底哪来的？** 它来自 **非容器化安装**（直接装 RabbitMQ 服务器）。那种安装方式下，`loopback_users.guest` 默认为 `true`，guest 确实只能本机登录。**是 Docker 镜像为了开发便利把它改掉了。**

**实验 C：一旦设置 `RABBITMQ_DEFAULT_USER`，guest 就消失了**

这才是你实际会遇到的事：

```bash
docker exec rabbitmq-learn rabbitmqctl list_users
# user    tags
# learn   [administrator]     ← 只有 learn，guest 不见了
```

此时用 `guest/guest` 连接，报的是：

```
ACCESS_REFUSED - Login was refused using authentication mechanism PLAIN.
```

注意这是**"用户不存在"**，不是"密码错误"——**你设了自定义账号之后，guest 这个用户本身就被删除了**。

> 🔒 **安全提醒**：本课用 `-management` 镜像 + 自定义账号，是正确做法。**但如果你用官方镜像的默认 guest 起服务，并且把 5672/15672 暴露到了公网，等于把管理员权限公开出去**——因为镜像放开了 loopback 限制。生产环境务必：建自定义账号、删掉 guest、或用防火墙/绑定地址限制来源。

**⑤ 数据持久化挂载（先知道，课 5 讲透）**

上面的命令**没有挂载卷，容器一删数据全没**。学习阶段无所谓，但要加是这样加：

```bash
docker run -d --name rabbitmq-learn \
  -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=learn \
  -e RABBITMQ_DEFAULT_PASS=learn123 \
  -v rabbitmq-data:/var/lib/rabbitmq \
  rabbitmq:4.3-management
```

`-v rabbitmq-data:/var/lib/rabbitmq` 把数据目录挂到一个命名卷上，容器删了数据还在。

#### 示例演示

**本课的教学容器，请用这条命令起**（和讲义保持一致，后面的输出才对得上）：

```bash
docker rm -f rabbitmq-learn 2>/dev/null
docker run -d --name rabbitmq-learn \
  -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=learn \
  -e RABBITMQ_DEFAULT_PASS=learn123 \
  rabbitmq:4.3-management
```

验证三件事（**这三条我都在本机跑过，输出是真实的**）：

```bash
# 1. 版本
docker exec rabbitmq-learn rabbitmqctl version
# 4.3.5

# 2. 监听了哪些端口
docker exec rabbitmq-learn rabbitmq-diagnostics listeners
# Interface: [::], port: 15672, protocol: http,        purpose: HTTP API
# Interface: [::], port: 15692, protocol: http/prometheus, purpose: Prometheus exporter API over HTTP
# Interface: [::], port: 25672, protocol: clustering,  purpose: inter-node and CLI tool communication
# Interface: [::], port: 5672,  protocol: amqp,        purpose: AMQP 0-9-1 and AMQP 1.0

# 3. 端口连通性自检（一条命令帮你确认没配错）
docker exec rabbitmq-learn rabbitmq-diagnostics check_port_connectivity
# Successfully connected to ports 5672, 15672, 15692, 25672 on node rabbit@07f37e4f56b5
```

> 💡 **`rabbitmq-diagnostics listeners` 是排错利器**：拿不准端口到底监听了没、监听在哪个网卡上，问它比猜快得多。

#### 常见误区

| ❌ 误区 | ✅ 正解 |
|--------|--------|
| 代码里 `port=15672` | `15672` 是给人看的界面；**代码一律连 5672** |
| `docker ps` 看到 Up 就开始连 | 要等日志出现 `Server startup complete`，通常 20–40 秒 |
| 用 `rabbitmq:latest` 学习 | 没有管理界面，且版本会漂移 |
| 起了自定义用户还用 guest 登录 | **自定义用户一设，guest 就被删了**，报 ACCESS_REFUSED |
| 以为容器删了数据还在 | 没挂卷 = 数据随容器消失 |
| 以为 Docker 镜像里 guest 也只能本机登录 | **官方镜像用 `loopback_users.guest = false` 放开了限制**（非容器安装才是默认本机） |
| 用默认 guest 起服务还把端口暴露到公网 | 镜像放开了限制 + 默认凭据 = **等于公开管理员权限**，务必建自定义账号 |

#### 一句话记住

**5672 是业务窗口（程序走），15672 是大屏（人走）；起服务要等 `Server startup complete`；设了自定义账号 guest 就被删，而官方 Docker 镜像本身就放开了 guest 的远程登录。**

#### 📚 官方文档

-  networking 与端口：[Networking and Ports](https://www.rabbitmq.com/docs/networking)
-  Docker 镜像：[RabbitMQ on Docker Hub](https://hub.docker.com/_/rabbitmq)

---

### 知识点 2：Management UI 巡礼

> 本知识点关键点：Overview / Queues / Exchanges 三个页签 / 内置的 amq.* 交换机 / 手动 publish 与 get

#### 一句话定义

**Management UI** 是 RabbitMQ 自带的 Web 管理界面，让你不用写代码就能看见 broker 里有哪些队列、交换机、绑定，还能手动发消息、取消息。

#### 直觉建立（类比）

如果说 CLI 是用命令行查邮局账目，那 Management UI 就是**邮局的实时大屏 + 控制台**：

- 大屏显示：今天收了多少件（消息速率）、积压多少（ready）、有几个快递员在岗（consumers）
- 控制台允许你：手动投一个测试包裹（publish）、手动取一个包裹看看（get）

> 💡 **类比的边界**：真实邮局不能把包裹"取出来看一眼再放回去"，但 RabbitMQ 的 `Get messages` 可以（选 ack 模式），这是调试特权，别在生产环境乱用。

#### 核心原理

浏览器打开 **http://localhost:15672** ，用 `learn` / `learn123` 登录。

**① 三个必看的页签**

| 页签 | 看什么 | 学习阶段的价值 |
|------|--------|---------------|
| **Overview** | 节点状态、消息速率总览、端口监听 | 确认"服务活着" |
| **Queues** | 队列列表：消息数、消费者数、是否持久化 | ⭐ **最常用**，看消息有没有到位 |
| **Exchanges** | 交换机列表及类型 | 下节课的主场 |

**Connections**（连接）和 **Channels**（信道）两个页签也很有用——**你的程序跑起来后，来这里确认连接真的建立了**，比看代码输出更可靠。

**② 内置的 amq.* 交换机**

刚起的服务，`Exchanges` 页签里**已经有 7 个交换机了**（实测输出）：

```bash
docker exec rabbitmq-learn rabbitmqctl list_exchanges
# Listing exchanges for vhost / ...
# name                 type
#                      direct          ← 注意这个空名字！就是默认交换机
# amq.direct           direct
# amq.fanout           fanout
# amq.headers          headers
# amq.match            headers
# amq.rabbitmq.log     topic
# amq.rabbitmq.trace   topic
# amq.topic            topic
```

**第一行那个名字为空的 `direct`，就是默认交换机（Default Exchange）。** 它是本课能"不声明交换机就发消息"的原因，下节课会重点讲它。

另外 6 个是预置的：

| 名字 | 类型 | 说明 |
|------|------|------|
| `amq.direct` | direct | 预置直连交换机 |
| `amq.fanout` | fanout | 预置广播交换机 |
| `amq.topic` | topic | 预置通配符交换机 |
| `amq.headers` / `amq.match` | headers | 两个都是 headers 类型（历史原因保留了两个别名） |
| `amq.rabbitmq.log` / `amq.rabbitmq.trace` | topic | **用于日志与消息追踪的内部交换机**，别动 |

> 💡 **`amq.rabbitmq.trace` 是个隐藏好东西**：配合 `rabbitmqctl trace_on`，能把你 broker 里流经的消息全部复制一份到指定队列，排查"消息到底去哪了"时非常有用。

**③ vhost 是什么**

UI 左上角有个 `Virtual host: /`。**vhost（虚拟主机）** 是 RabbitMQ 里的**命名空间隔离单位**——不同 vhost 里可以有同名队列，互相完全看不见。默认是 `/`。

> 类比：**vhost 就像一栋楼里的不同公司**，各用各的邮筒，互不干扰。权限（Permissions）也是按 vhost 授予的。

#### 示例演示

**在 UI 里手动发一条消息**（不写一行代码）：

1. 点 **Exchanges** → 找到名字为空的那一行（默认交换机）→ 点进去
2. 展开 **Publish message**
3. `Routing key` 填 `hello`，`Payload` 填 `来自管理界面的消息`
4. 点 **Publish** → 出现 `Message published` 就是成功了
5. 点 **Queues** → `hello` 那一行的 `Ready` 应该从 0 变成 1
6. 点进 `hello` 队列 → 展开 **Get messages** → `Ack Mode` 选 `Nack message requeue true`（**只看不消费**）→ 点 **Get**

> ⚠️ **`Ack Mode` 的选择很关键**：选 `requeue true` 是"看一眼放回去"（调试用），选 `ack` 是"真的取走"。**第一次试建议用 requeue true**，避免把消息消费掉导致后续实验没数据。

**等价的 HTTP API 写法**（实测通过，脚本在 `playground/verify.sh`）：

```bash
# 手动发一条
curl -s -u learn:learn123 -H "Content-Type: application/json" \
  -X POST http://localhost:15672/api/exchanges/%2F/amq.default/publish \
  -d '{"properties":{},"routing_key":"hello","payload":"来自管理界面的消息","payload_encoding":"string"}'
# 返回：{"routed":true}

# 手动取一条（ackmode=ack_requeue_false 表示真的取走）
curl -s -u learn:learn123 -H "Content-Type: application/json" \
  -X POST http://localhost:15672/api/queues/%2F/hello/get \
  -d '{"count":5,"ackmode":"ack_requeue_false","encoding":"auto"}'
# 返回：[{"payload_bytes":27,"redelivered":false,"exchange":"","routing_key":"hello",
#        "message_count":0,"properties":[],"payload":"来自管理界面的消息","payload_encoding":"string"}]
```

> 💡 **`%2F` 是 vhost `/` 的 URL 编码**。vhost 名叫 `/` 这个设计让 URL 写起来很反直觉，这是新手调 API 时的高频卡点。
> 💡 **`{"routed":true}` 这个返回值很有价值**：`true` 表示消息**成功路由到了至少一个队列**。如果是 `false`，说明没有任何队列匹配——**消息被静默丢弃了**。这是排查"消息发了但队列没有"的第一诊断点。

#### 常见误区

| ❌ 误区 | ✅ 正解 |
|--------|--------|
| 在 UI 里 Get 消息后队列空了，以为丢消息 | `Ack Mode` 选了 ack = 真的取走了；调不推荐用 `requeue true` |
| 找不到自己声明的交换机 | 默认交换机名字是**空字符串**，显示为空白行 |
| 队列同名冲突 | 先确认 UI 左上角 vhost 是不是同一个 |
| 手动 publish 返回 `{"routed":false}` 却没在意 | **消息被丢弃了**，没有任何队列匹配这个 routing key |

#### 一句话记住

**Queues 页签看消息到没到，Exchanges 页签里那行空名字的就是默认交换机；`routed:true` 才是真发到了。**

#### 📚 官方文档

- Management UI 指南：[Management Plugin](https://www.rabbitmq.com/docs/management)
- HTTP API 参考：[Management HTTP API](https://www.rabbitmq.com/docs/management#http-api)

---

### 知识点 3：Python 发第一条消息

> 本知识点关键点：pika 安装 / 建立连接与信道 / queue_declare + basic_publish + basic_consume

> 🔥 **这是本课的核心，也是全网教程最容易翻车的地方。我会把两个必踩的坑连同报错原文一起给你，让你踩上去的时候认得它。**

#### 一句话定义

用 Python 的 **pika** 客户端连上 5672 端口，声明一个队列，用 `basic_publish` 发一条消息，再用 `basic_consume` 把它收回来——这就是 AMQP 世界的 "Hello World"。

#### 直觉建立（类比）

回到邮局。寄一个包裹的完整动作是：

1. **找到邮局**（建立 TCP 连接 → `5672`）
2. **开一个业务窗口**（建立信道 Channel）
3. **确认收件格子存在**（声明队列 `queue_declare`）
4. **把包裹递进去**（发布 `basic_publish`）
5. **收件人等着，包裹一到就送上门**（消费 `basic_consume`）

> 💡 **类比的关键点**：第 5 步是**送货上门**（推送 push），不是收件人跑邮局问（轮询 pull）。这是 RabbitMQ 消费模型的核心，**消息是被推给你的**。
> 💡 **类比的边界**：真实邮局里"确认格子存在"是邮局的事；在 RabbitMQ 里**这一步要你自己做**——而且**生产者和消费者都要做**，原因见下文。

#### 核心原理

**① 连接（Connection）与信道（Channel）**

```python
connection = pika.BlockingConnection(parameters)   # TCP 连接，重资源
channel = connection.channel()                      # 信道，轻资源
```

课 2 讲过：**一条 TCP 连接上可以开多条信道**，信道才是实际干活的。类比：TCP 连接是**一条公路**，信道是公路上的**车道**——修路贵，划车道便宜。

**② 三个核心方法**

| 方法 | 作用 | 谁调用 |
|------|------|--------|
| `queue_declare` | 声明队列（**幂等**：已存在且参数一致则什么都不做） | 生产者 **和** 消费者都要 |
| `basic_publish` | 发消息到交换机 | 生产者 |
| `basic_consume` | 注册消费者，消息会被推送过来 | 消费者 |

> ❓ **为什么生产者和消费者都要声明队列？**
> 因为你**无法保证谁先启动**。如果消费者先跑而队列还不存在，它就会订阅一个不存在的队列而报错。两边都声明，谁先跑都能把队列建起来——这就是"幂等"的价值：**同样的声明执行一百次，效果和执行一次一样。**

**③ 幂等是有条件的（坑 #2 的本质）**

`queue_declare` 幂等，**但要求参数完全一致**。如果队列 `hello` 已经以 `durable=True` 存在，你再用 `durable=False` 声明，broker 会拒绝：

```
PRECONDITION_FAILED - inequivalent arg 'durable' for queue 'hello' in vhost '/':
received 'false' but current is 'true'
```

**队列一旦创建，durable / exclusive / auto-delete / arguments 这些属性就改不了了。** 要改只能删队列重建（**会丢消息**）。

#### 🐞 坑 #1：4.3 起，非持久化的非排他队列被默认禁止

这是本课最重要的内容。

**现象**：照着网上教程写 `channel.queue_declare(queue='hello')`，连接被 broker 直接掐断：

```
pika.exceptions.ConnectionClosedByBroker: (541, 'INTERNAL_ERROR - Feature `transient_nonexcl_queues` is deprecated.
By default, this feature is not permitted anymore.
The feature will be removed in a future major RabbitMQ version, regardless of the configuration;
actual version to be determined. To...')
```

**根因**（核查于 2026-08，RabbitMQ 4.3.0 release notes + 官方 Queues 文档）：

这个 `transient_nonexcl_queues` 特性从 **2021 年 8 月**就开始弃用，处于"默认允许"状态。到 **4.3.0（2026-04-23 发布）**，它的弃用阶段从 `permitted_by_default` 推进到 **`denied_by_default`**——**默认禁止，必须显式 opt-in 才能用**。

被禁止的是这个组合：

| 属性 | 值 | 说明 |
|------|-----|------|
| `durable` | `False` | 非持久化（transient） |
| `exclusive` | `False` | 非排他 |

而 pika 的 `queue_declare` **默认就是 `durable=False, exclusive=False`**——正好命中被禁的组合。所以**网上几乎所有老教程的第一行代码，在 4.3 上都是跑不通的**。

**为什么官方要禁它？** 官方给出的理由（GitHub commit 说明）很实在：

> 瞬态队列会在节点重启时被删除。**应用开发者无法依赖"节点重启"这种随机事件来推理队列的生命周期。**

**解法有三条，按推荐度排序：**

| 解法 | 做法 | 适用 |
|------|------|------|
| ✅ **推荐**：声明为持久化队列 | `queue_declare(queue='hello', durable=True)` | **绝大多数场景**，本课采用 |
| ✅ 需要临时队列时：排他队列 | `queue_declare(queue='', exclusive=True)` | 队列名留空让服务端生成，连接断开自动删除 |
| ⚠️ 临时放开限制（不推荐） | 配置 `deprecated_features.permit.transient_nonexcl_queues = true` | 仅存量系统迁移期过渡，未来版本会彻底移除 |

> ⚠️ **第三条为什么是"临时"**：官方明确说这个特性**会在未来的大版本被彻底移除**（"will be removed in a future major RabbitMQ version, regardless of the configuration"）。也就是说，配了这个开关只是缓刑，**该改的代码早晚要改**。
> ⚠️ **注意 `durable=True` 不等于消息不丢**：它只保证**队列本身**在重启后还在。消息是否持久化由发布时的 `delivery_mode` 决定——**这是课 5 和课 7 的内容**，本课先不展开，但你要知道这里有第二层开关。

#### 示例演示：完整跑通

**第 0 步：装 pika**

```bash
python3 -m pip install pika
# 实测环境：pika 1.4.4 + Python 3.12
```

> 💡 **本机环境提示**：你这台 Windows 上没有直接的 Python，但 **WSL 里有 Python 3.12**。讲义代码在 `playground/` 目录下，用 WSL 的 bash 运行即可（我实测就是这么跑的）：
>
> ```bash
> # Windows PowerShell 里这样调（D 盘在 WSL 中挂载为 /mnt/d）
> & "C:\Windows\System32\bash.exe" -c "bash /mnt/d/projects/learning/rabbitmq/playground/verify.sh"
> ```
>
> 配套文件：
>
> | 文件 | 作用 |
> |------|------|
> | `playground/send.py` | 生产者，发一条 `Hello RabbitMQ!` |
> | `playground/receive.py` | 消费者，收到后打印并一直等待 |
> | `playground/verify.sh` | **一键跑完整流程**：清空 → 发送 → 查队列 → 消费 → 再查队列 → 看绑定 → 健康检查 |

**第 1 步：生产者 `send.py`**

```python
import pika

# 1. 建立 TCP 连接：5672 是 AMQP 协议端口，15672 是管理界面端口，别搞混
credentials = pika.PlainCredentials('learn', 'learn123')
parameters = pika.ConnectionParameters(host='localhost', port=5672, credentials=credentials)
connection = pika.BlockingConnection(parameters)

# 2. 在 TCP 连接之上开一条信道（channel）：真正干活的都是信道，不是连接
channel = connection.channel()

# 3. 声明队列：durable=True 在 RabbitMQ 4.3 是必须的（见上文坑 #1）
#    这个操作是幂等的——队列已存在且参数一致时不会重复创建
channel.queue_declare(queue='hello', durable=True)

# 4. 发消息：exchange 留空 = 走默认交换机，routing_key 直接填队列名
channel.basic_publish(
    exchange='',
    routing_key='hello',
    body='Hello RabbitMQ!'
)
print(" [x] 已发送 Hello RabbitMQ!")

# 5. 关闭连接
connection.close()
```

**第 2 步：消费者 `receive.py`**

```python
import pika

credentials = pika.PlainCredentials('learn', 'learn123')
parameters = pika.ConnectionParameters(host='localhost', port=5672, credentials=credentials)
connection = pika.BlockingConnection(parameters)
channel = connection.channel()

# 消费者这边也要声明：你无法保证生产者一定先跑过。
# 注意 durable 参数必须和生产者完全一致，否则报 PRECONDITION_FAILED（坑 #2）
channel.queue_declare(queue='hello', durable=True)


# 回调函数：消息是被"推"给我们的，不是我们去轮询拉取
def on_message(ch, method, properties, body):
    # flush=True：输出被管道重定向时 Python 会缓冲，不加可能在超时被杀时丢输出
    print(f" [x] 收到 {body.decode()}", flush=True)


# 注册消费者：auto_ack=True 表示一收到就自动确认（课 6 会讲为什么生产环境不该这么干）
channel.basic_consume(
    queue='hello',
    auto_ack=True,
    on_message_callback=on_message
)

print(' [*] 等待消息中。按 CTRL+C 退出')
channel.start_consuming()
```

**第 3 步：跑起来，并用 CLI 验证**

```bash
# 终端 1：发消息
python3 send.py
#  [x] 已发送 Hello RabbitMQ!

# 观察队列：消息确实躺在里面
docker exec rabbitmq-learn rabbitmqctl list_queues name messages consumers durable type
# name    messages    consumers    durable    type
# hello   1           0            true       classic
#                     ↑ 没人消费，所以是 1

# 终端 2：收消息
timeout 6 python3 receive.py
#  [*] 等待消息中。按 CTRL+C 退出
#  [x] 收到 Hello RabbitMQ!

# 再看队列：被消费掉了
docker exec rabbitmq-learn rabbitmqctl list_queues name messages consumers durable type
# name    messages    consumers    durable    type
# hello   0           0            true       classic
#                     ↑ 消费完归零
```

> 🎯 **这就是"回扣第一幕"的时刻**：你在 UI 的 Queues 页签里能看到 `Ready` 从 0 → 1 → 0 的完整变化。**消息确实进了一个真实存在的中间节点，而不是直接从一个进程跳到另一个进程。** 这就是第 1 课讲的"异步"真实发生的证据。

**第 4 步：确认默认交换机帮我们做了什么**

```bash
docker exec rabbitmq-learn rabbitmqctl list_bindings source_name destination_name routing_key
# source_name    destination_name    routing_key
#                hello               hello
# ↑ 空 = 默认交换机
```

**每个队列在创建时，都会自动以"队列名"为 routing key 绑定到默认交换机。** 这就是为什么 `exchange=''` + `routing_key='hello'` 能直接把消息送到 `hello` 队列——**下节课会把这层机制彻底讲透**。

#### 常见误区

| ❌ 误区 | ✅ 正解 |
|--------|--------|
| `queue_declare(queue='hello')` 报错是环境坏了 | **4.3 默认禁止非持久化非排他队列**，加 `durable=True` |
| 改了 `durable` 还是报 PRECONDITION_FAILED | 队列已存在且属性不同，**删了重建**：`rabbitmqctl delete_queue hello` |
| 只在生产者声明队列 | **两边都要声明**，你无法保证启动顺序 |
| 消费者收不到消息就狂改代码 | 先看 UI 的 Queues 页签：`Ready` 是 0 说明**根本没发进来**，问题在生产者 |
| 用 `basic_get` 轮询代替 `basic_consume` | 消费模型是**推送**，轮询是调试手段（而且性能差） |
| 以为 `durable=True` 消息就不会丢 | 队列持久 ≠ 消息持久，消息还要 `delivery_mode=2`（**课 5**） |

#### 一句话记住

**连接 5672 开信道，两边都 `queue_declare(durable=True)`，生产者 `basic_publish` 发、消费者 `basic_consume` 收——`auto_ack=True` 只是教学省力，生产别这么干。**

#### 📚 官方文档

- Python 官方教程（Hello World）：[RabbitMQ tutorial one — Python](https://www.rabbitmq.com/tutorials/tutorial-one-python)
- pika 文档：[pika documentation](https://pika.readthedocs.io/)
- 队列持久性说明：[Queues — Durability](https://www.rabbitmq.com/docs/queues#durability)
- 弃用特性清单：[List of Deprecated Features](https://www.rabbitmq.com/release-information/deprecated-features-list)

---

### 知识点 4：CLI 常用命令

> 本知识点关键点：list_queues / list_exchanges / list_bindings / 节点与诊断命令

#### 一句话定义

RabbitMQ 提供三个命令行工具：**`rabbitmqctl`**（运维管理，最常用）、**`rabbitmqadmin`**（走 HTTP API，输出友好）、**`rabbitmq-diagnostics`**（健康检查与排障）。

#### 直觉建立（类比）

三个工具，三种身份：

| 工具 | 类比 | 特点 |
|------|------|------|
| `rabbitmqctl` | **邮局局长的内部工作台** | 直接连节点，**功能最全**，输出朴素 |
| `rabbitmqadmin` | **给外部伙伴的查询窗口** | 走 HTTP API，**输出是表格**，适合人看 |
| `rabbitmq-diagnostics` | **体检医生** | 只管健康检查与诊断 |

> 💡 **学习阶段主用 `rabbitmqctl`**，它是所有文档和运维手册里的通用语言；`rabbitmqadmin` 适合你想要好看的表格输出时。

#### 核心原理

**① rabbitmqctl：查询四件套**

```bash
# 队列：最常用的一句
rabbitmqctl list_queues name messages consumers durable type

# 交换机
rabbitmqctl list_exchanges name type

# 绑定（看路由关系，下节课的主角）
rabbitmqctl list_bindings source_name destination_name routing_key

# 连接与信道（看你的程序有没有真的连上）
rabbitmqctl list_connections
rabbitmqctl list_channels
```

> 💡 **`list_queues` 后面跟的是"你想要的列名"**，不写就只给名字。常用的列：`name`、`messages`、`messages_ready`（待投递）、`messages_unacknowledged`（已投递未确认）、`consumers`、`durable`、`type`、`memory`。
> 💡 **`messages_ready` vs `messages_unacknowledged` 是排障黄金指标**：
> - `unacked` 持续堆积 → **消费者处理太慢或卡住了**
> - `ready` 持续堆积 → **消费能力不足或没有消费者**
> 课 6 讲完确认机制后，这两个指标会成为你最重要的诊断依据。

**② rabbitmqctl：运维动作**

```bash
rabbitmqctl delete_queue hello     # 删队列（改属性报错时的唯一出路）
rabbitmqctl purge_queue hello      # 清空队列里的消息，保留队列本身
rabbitmqctl list_vhosts            # 看 vhost
rabbitmqctl list_users             # 看用户
rabbitmqctl add_user <user> <pass> # 建用户
rabbitmqctl set_permissions -p / <user> ".*" ".*" ".*"   # 授权
```

> ⚠️ **`delete_queue` 和 `purge_queue` 都会丢消息，且不可恢复。** 生产环境执行前请三思。

**③ rabbitmqadmin：新版语法变了（实测踩坑）**

> ⚠️ **这是本课第三个坑。** 网上大量教程写的 `rabbitmqadmin list queues name messages` 这种"命令后跟列名"的写法，在 **2.x 新版（实测 2.34.0）已经失效**：

```
error: unexpected argument 'name' found
Usage: rabbitmqadmin list queues [OPTIONS]
```

新版是**子命令结构**，列名不再跟在后面，而是**输出固定的一组列**。正确用法：

```bash
# 新版正确写法（实测通过）
rabbitmqadmin list queues --non-interactive
# hello  /  classic  true  false  false  x-queue-type: "classic"  rabbit@07f37e4f56b5  running  ...

rabbitmqadmin list exchanges --non-interactive
#                     /  direct   true  false
# amq.direct           /  direct   true  false
# amq.fanout           /  fanout   true  false
# amq.headers          /  headers  true  false
# amq.match            /  headers  true  false
# amq.rabbitmq.log     /  topic    true  false
# amq.rabbitmq.trace   /  topic    true  false
# amq.topic            /  topic    true  false

rabbitmqadmin list bindings --non-interactive
# /    hello  queue  hello    hello
```

**凭据怎么给**：新版用环境变量（实测通过）：

```bash
export RABBITMQADMIN_USERNAME=learn
export RABBITMQADMIN_PASSWORD=learn123
rabbitmqadmin list queues --non-interactive
```

不给凭据会直接报 `Not_Authorized`。

常用参数：

| 参数 | 作用 |
|------|------|
| `--non-interactive` | 脚本里调用时加上，避免交互提示 |
| `-V <vhost>` | 指定 vhost，默认 `/` |
| `--table-style <style>` | 表格样式：`modern` / `markdown` / `ascii` / `psql` 等 |
| `--page-size <n>` | 分页，默认 100，最大 500 |

> 💡 **`rabbitmqadmin` 还有个版本坑**：它**不在容器镜像的固定路径里**，官方推荐从运行中的节点下载（`http://localhost:15672/cli/rabbitmqadmin`）以保证版本匹配。实测**当前 4.3 镜像里已经自带了**（`/usr/local/bin/rabbitmqadmin`，版本 2.34.0），直接 `docker exec` 里跑就行。

**④ rabbitmq-diagnostics：健康检查三板斧**

```bash
rabbitmq-diagnostics status          # 整体状态：版本、Erlang、内存、插件
rabbitmq-diagnostics check_running   # 节点是否完全启动
rabbitmq-diagnostics check_port_connectivity   # 端口连通性自检
rabbitmq-diagnostics listeners       # 实际监听了哪些端口
rabbitmq-diagnostics check_local_alarms        # 资源告警（内存/磁盘）
```

实测输出：

```bash
docker exec rabbitmq-learn rabbitmq-diagnostics check_running
# RabbitMQ on node rabbit@07f37e4f56b5 is fully booted and running

docker exec rabbitmq-learn rabbitmq-diagnostics check_local_alarms
# Node rabbit@07f37e4f56b5 reported no local alarms
```

> ⚠️ **实测发现**：`check_local_alarms` 会打印一行 `This command is DEPRECATED and is a no-op. It will be removed in a future version.`——它已经**变成空操作**了。想看资源告警，改用 `rabbitmq-diagnostics status | grep -i alarm` 或 `memory_breakdown`。**（这是我在备课实测中发现的，网上教程基本都还在推荐这条命令。）**

> 💡 **`check_port_connectivity` 我特别推荐**：一条命令同时验证 5672 / 15672 / 15692 / 25672 全部可达。**当你"连不上"时，先用它排除端口问题，能省半小时。**

#### 示例演示：一次完整的排查演练

**场景**：你跑了 `send.py`，程序显示"已发送"，但消费者什么都没收到。

```bash
# 第 1 步：消息到底进队列了吗？
docker exec rabbitmq-learn rabbitmqctl list_queues name messages messages_ready messages_unacknowledged
# name    messages    messages_ready    messages_unacknowledged
# hello   1           1                 0
#         ↑ 消息在队列里，说明生产者没问题，问题在消费者

# 第 2 步：有消费者连着吗？
docker exec rabbitmq-learn rabbitmqctl list_queues name consumers
# name    consumers
# hello   0
#         ↑ 0 个消费者！你的消费者进程没跑，或者连的是别的 vhost

# 第 3 步：看看有没有连接
docker exec rabbitmq-learn rabbitmqctl list_connections
# （空 = 根本没有客户端连上来）

# 第 4 步：服务本身健康吗？
docker exec rabbitmq-learn rabbitmq-diagnostics check_port_connectivity
docker exec rabbitmq-learn rabbitmq-diagnostics check_running
```

**这就是真实的排查顺序：先看消息到没到 → 再看有没有消费者 → 再看连接 → 最后怀疑服务本身。**

> 💡 这个"先定位在哪一端"的思路，会在课 9（工程实践）和 Phase 5（排障速查手册）里反复用到。

#### 常见误区

| ❌ 误区 | ✅ 正解 |
|--------|--------|
| 照抄老教程 `rabbitmqadmin list queues name messages` | **2.x 新版不支持列名参数**，直接 `list queues` |
| `rabbitmqadmin` 报 `Not_Authorized` | 用 `RABBITMQADMIN_USERNAME/PASSWORD` 环境变量给凭据 |
| 用 `rabbitmqctl` 查消息内容 | 它**只查元数据不查消息体**，看消息内容用 UI 的 Get 或 HTTP API |
| 以为 `check_local_alarms` 还在工作 | **已废弃为空操作**，改用 `status` |
| 连不上就怀疑 RabbitMQ 坏了 | 先跑 `check_port_connectivity` 排除端口问题 |

#### 一句话记住

**`rabbitmqctl list_queues` 查状态、`list_bindings` 查路由、`rabbitmq-diagnostics check_port_connectivity` 查连通；消费者收不到消息，先看 `consumers` 是不是 0。**

#### 📚 官方文档

- CLI 工具指南：[Command Line Tools](https://www.rabbitmq.com/docs/cli)
- rabbitmqctl 参考：[rabbitmqctl(8)](https://www.rabbitmq.com/docs/rabbitmqctl.8)
- 监控与健康检查：[Monitoring and Health Checks](https://www.rabbitmq.com/docs/monitoring)

---

## 第五幕：体系收束

### 本课在全局中的位置

回想第 1 课那张"没有 MQ 的下单系统"，和第 2 课那些砸晕你的名词。今天它们**全部落到了地上**：

| 第 2 课的名词 | 今天你做的事 |
|---------------|-------------|
| Broker（消息代理） | 用 Docker 起了一个真实的 broker |
| Exchange（交换机） | 在 UI 里看见了 7 个内置的，还用默认交换机发了消息 |
| Queue（队列） | 声明了 `hello`，看着它的消息数从 0 → 1 → 0 |
| Binding（绑定） | 看到 `hello` 队列自动绑定到默认交换机 |
| Connection / Channel | 用 pika 建立了连接，在上面开了信道 |
| vhost | 认识了默认的 `/` |

**你现在能回答"消息到底去哪了"这个第 1 课提出的核心问题**：它进了一个真实存在的中间节点（broker），停在一个真实的队列里，等着被取走——**而不是从一个进程直接跳进另一个进程**。

### 最小闭环已经跑通

```
你的 Python 程序  --5672-->  [交换机]  -->  [队列 hello]  --推送-->  你的 Python 程序
                     ↑                          ↑
                 默认交换机              消息在这里停留过
              （下节课的主角）          （这就是"异步"的证据）
```

### 你现在会了什么

- ✅ 一条命令起 RabbitMQ，说清 5672（程序）与 15672（人）的分工
- ✅ 在 Management UI 里看队列、交换机、绑定，手动发消息和取消息
- ✅ 用 pika 写出能跑通的最小收发程序
- ✅ 用 CLI 查出"消息到没到、有没有消费者、服务健不健康"

### 接下来学什么，以及为什么

今天有个问题被我**刻意搁置**了：为什么 `exchange=''` 留空、`routing_key` 填队列名，消息就能到 `hello`？

答案是**默认交换机**——它把所有队列都按队列名自动绑定好了。这是个特例，是个"新手福利"。

**但 RabbitMQ 真正的威力不在这里。** 它最核心的设计是**交换机和队列分离**：生产者只管把消息交给交换机，交换机按规则决定消息该进哪些队列。**正是这一层，让 RabbitMQ 的路由能力远超同类产品**——一条消息可以同时触发扣库存、发短信、加积分，而生产者根本不需要知道有几个下游。

**下一课《交换机与路由》，就要拆开这层设计。** 学完它，你才能真正回答第 1 课那个"每加一个下游就要改一次核心代码"的问题。

> 🚀 **埋个伏笔**：下节课你会看到 `fanout`（广播）如何让一条消息同时进多个队列，也会看到 `routed:false`（消息被丢弃）在什么情况下会发生——今天在 UI 里见过的那个 `amq.fanout`，马上就要派上用场了。

---

## 🐞 本课踩坑清单

这一课是本课程**踩坑密度最高**的一课，四个坑我全部实测复现过：

| # | 坑 | 报错 | 解法 |
|---|-----|------|------|
| 1 | 4.3 禁止非持久化非排他队列 | `INTERNAL_ERROR - Feature 'transient_nonexcl_queues' is deprecated` | `queue_declare(durable=True)` |
| 2 | 队列属性不可更改 | `PRECONDITION_FAILED - inequivalent arg 'durable'` | 删队列重建：`rabbitmqctl delete_queue hello` |
| 3 | rabbitmqadmin 新版语法变了 | `error: unexpected argument 'name' found` | 去掉列名，`list queues --non-interactive` |
| 4 | 设了自定义用户后 guest 消失 | `ACCESS_REFUSED` | 用你设的账号登录（本课是 `learn`/`learn123`） |

> ⚠️ **另有一个"反直觉但重要"的发现**（不是坑，是安全提醒）：**官方 Docker 镜像里 guest 可以从任何地方登录**——镜像的 `10-defaults.conf` 写了 `loopback_users.guest = false`，与"guest 只能本机登录"的常见说法相反。网上几乎所有教程都在这里写错了。**别用默认 guest 把端口暴露到公网。**

> 💡 **额外提醒**：Python 输出被管道重定向时会缓冲，消费者在 `timeout` 被杀时可能什么都看不到。回调里的 `print` 加 `flush=True` 可解。

---

## 📋 命令速查卡

```bash
# ===== 起服务 =====
docker run -d --name rabbitmq-learn -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=learn -e RABBITMQ_DEFAULT_PASS=learn123 \
  rabbitmq:4.3-management
docker logs -f rabbitmq-learn          # 等 "Server startup complete"

# ===== rabbitmqctl：查询 =====
rabbitmqctl version
rabbitmqctl list_queues name messages consumers durable type
rabbitmqctl list_exchanges name type
rabbitmqctl list_bindings source_name destination_name routing_key
rabbitmqctl list_connections
rabbitmqctl list_vhosts
rabbitmqctl list_users

# ===== rabbitmqctl：动作 =====
rabbitmqctl delete_queue <name>        # 删队列（丢消息！）
rabbitmqctl purge_queue <name>         # 清空消息（丢消息！）

# ===== rabbitmqadmin（新版语法） =====
export RABBITMQADMIN_USERNAME=learn RABBITMQADMIN_PASSWORD=learn123
rabbitmqadmin list queues --non-interactive
rabbitmqadmin list exchanges --non-interactive
rabbitmqadmin list bindings --non-interactive

# ===== rabbitmq-diagnostics =====
rabbitmq-diagnostics check_running
rabbitmq-diagnostics check_port_connectivity
rabbitmq-diagnostics listeners
rabbitmq-diagnostics status

# ===== HTTP API =====
curl -s -u learn:learn123 http://localhost:15672/api/overview
curl -s -u learn:learn123 http://localhost:15672/api/queues
# 手动发消息（%2F = vhost "/"）
curl -s -u learn:learn123 -H "Content-Type: application/json" \
  -X POST http://localhost:15672/api/exchanges/%2F/amq.default/publish \
  -d '{"properties":{},"routing_key":"hello","payload":"test","payload_encoding":"string"}'
```

---

## 课后小测

**Q1**：你的 Python 程序连不上 RabbitMQ，报 `ConnectionRefusedError`。检查发现代码里写的是 `port=15672`。问题在哪？

- A. 15672 端口没映射出来
- B. 15672 是管理界面端口，程序应该连 5672
- C. 密码写错了
- D. 需要先声明队列才能连接

<details><summary>答案与解析</summary>

**答案：B**。**5672 是 AMQP 协议端口（程序走），15672 是 Management UI / HTTP API 端口（人走）**。这是本课最基础的分界线。A 不对——端口映射本身可能是正常的；C 会导致 `ACCESS_REFUSED` 而不是 `ConnectionRefused`；D 完全无关。
</details>

**Q2**：你照着网上的教程写了 `channel.queue_declare(queue='hello')`，在 RabbitMQ 4.3 上连接被掐断。最正确的应对是？

- A. 重装 RabbitMQ，肯定是镜像坏了
- B. 在配置文件里加 `deprecated_features.permit.transient_nonexcl_queues = true`
- C. 改成 `queue_declare(queue='hello', durable=True)`
- D. 换个旧版本的 RabbitMQ

<details><summary>答案与解析</summary>

**答案：C**。4.3.0 起，`transient_nonexcl_queues`（非持久化 + 非排他队列）的弃用阶段推进到**默认禁止**，而 pika 默认正是这个组合。官方推荐改用持久化队列。

B 能work但**不推荐**——官方明确说这个特性会在未来大版本彻底移除，配置它只是缓刑，该改的代码早晚要改。A 和 D 属于治标不治本，回避了真正的问题。
</details>

**Q3**：你把代码改成了 `durable=True`，结果报 `PRECONDITION_FAILED - inequivalent arg 'durable' ... received 'false' but current is 'true'`。为什么？

- A. 生产者不能声明队列
- B. 队列已经以 `durable=False` 存在，属性不能改
- C. `durable=True` 这个参数名写错了
- D. 需要先清空队列才能改属性

<details><summary>答案与解析</summary>

**答案：B**。**队列一旦创建，durable / exclusive / auto-delete / arguments 这些属性就固定了**，`queue_declare` 的幂等性只在"参数完全一致"时成立。解法是 `rabbitmqctl delete_queue hello` 删掉重建（**注意会丢消息**）。

A 不对——生产者当然可以且应该声明队列；C 参数名没错；D 清空消息（purge）不改变队列属性，没用。
</details>

**Q4**（多选题）：关于默认账号 `guest`，以下哪些说法是**正确**的？

- A. 官方 Docker 镜像里，默认的 guest/guest **可以从任何地方登录**
- B. 一旦用 `RABBITMQ_DEFAULT_USER` 设置了自定义用户，guest 用户会被删除
- C. 非容器化安装的 RabbitMQ，guest 默认只能从本机登录
- D. 用默认 guest 起服务并暴露到公网是安全的，因为 guest 只能本机访问

<details><summary>答案与解析</summary>

**答案：A、B、C**。

A 正确——**这是本课最具反直觉色彩的实测发现**：官方镜像的 `/etc/rabbitmq/conf.d/10-defaults.conf` 里写着 `loopback_users.guest = false`，并自我标注"默认设置不应直接用于生产"。实测从容器外用 guest 连 5673 和调 HTTP API 都成功。

B 正确——实测 `list_users` 在设了自定义账号后只剩该账号，此时用 guest 连接报 `ACCESS_REFUSED`（是"用户不存在"，不是"密码错"）。

C 正确——这正是"guest 只能本机登录"这个流行说法的真正来源；**Docker 镜像为了开发便利改掉了它**。

D **错误且危险**——A 成立意味着这个假设完全不成立，暴露到公网等于公开管理员权限。
</details>

**Q5**：消费者收不到消息。你执行 `rabbitmqctl list_queues name messages consumers` 看到 `hello 5 0`。这说明什么？

- A. broker 出问题了，消息发不进去
- B. 消息已经成功进入队列，但没有消费者在消费
- C. 消费者消费了 5 条消息
- D. 消息被丢弃了

<details><summary>答案与解析</summary>

**答案：B**。`messages=5` 说明**生产者工作正常**（消息确实进了队列），`consumers=0` 说明**没有任何消费者连接**。问题在消费端：消费者进程没启动、连错了 vhost、或者订阅了别的队列名。

这正是本课教的排查顺序：**先看消息到没到，再看有没有消费者，最后才怀疑服务本身**。
</details>

---

## 📚 官方文档

- RabbitMQ 官方文档（当前 4.3.5）：https://www.rabbitmq.com/docs/
- Docker 镜像：https://hub.docker.com/_/rabbitmq
- 网络与端口：https://www.rabbitmq.com/docs/networking
- Python 官方教程（Hello World）：https://www.rabbitmq.com/tutorials/tutorial-one-python
- 队列与持久性：https://www.rabbitmq.com/docs/queues
- 弃用特性清单：https://www.rabbitmq.com/release-information/deprecated-features-list
- CLI 工具：https://www.rabbitmq.com/docs/cli

---

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课（无需重新描述上下文）：

```
继续学 RabbitMQ。我的学习档案在 rabbitmq/00-学习档案.md，
刚学完阶段 2《核心模型与上手》的课 3《起 RabbitMQ 与发第一条消息》知识点 Docker 起服务与端口、Management UI 巡礼、Python 发第一条消息、CLI 常用命令，
请按大纲继续讲解下一课 课 4《交换机与路由》的知识点。
```

## 🧭 课程导航

⬅️ **上一课**：[课 2 · RabbitMQ 是什么与起源定位](../../1-为什么需要消息队列/lessons/lesson-02-RabbitMQ是什么与起源定位.md)

➡️ **下一课**：[课 4 · 交换机与路由](lesson-04-交换机与路由.md)

🎯 **返回目录**：[课程目录](../../02-课程目录.md)