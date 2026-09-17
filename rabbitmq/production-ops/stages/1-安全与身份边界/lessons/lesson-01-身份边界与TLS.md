# 课 1：身份边界与 TLS

> 阶段 1 · 安全与身份边界 ｜ 本课 3 个知识点 ｜ 版本基线：RabbitMQ 4.3.5

## 本课要解决的真实问题

你已经能用 `learn` 用户连接 RabbitMQ，消息也能正常发布和消费。然后服务要从开发机搬到生产：连接不能再明文传输，应用不能共享管理员账号，运维人员不能因为“方便”拿到业务队列的写权限。

这时要同时回答三个问题：**你是谁（认证）？你能做什么（授权）？别人能不能窃听或冒充你（TLS）？**

## 第一幕：一条“能连上”的连接并不安全

开发环境里最容易形成一个危险错觉：只要 `pika.BlockingConnection(...)` 不报错，RabbitMQ 就已经配置好了。

但一条连接可能同时存在三种漏洞：

1. 使用默认或共享账号，无法定位是谁在操作；
2. 用户能登录，但对不该访问的 vhost / 队列拥有权限；
3. 使用明文 AMQP，凭据和消息都暴露在网络路径上。

## 第二幕：认知冲突——认证、授权、加密不是一回事

把三件事混成“用户名密码”会让排障方向完全错位：

| 问题 | RabbitMQ 负责的层 | 失败时典型现象 |
|------|------------------|----------------|
| 你是谁？ | 认证（authentication） | `ACCESS_REFUSED - Login was refused` |
| 你能做什么？ | 授权（authorization） | `access to queue ... refused` |
| 传输是否可信？ | TLS / 证书校验 | TLS handshake / certificate verify 失败 |

**一句话冲突**：TLS 不能替你授予队列权限；拥有权限的账号也不能证明连接没有被窃听。

## 第三幕：层层揭示

### 知识点 1：认证、授权、vhost 与权限正则

#### 一句话定义

- **认证**决定用户能否登录。
- **vhost** 是权限隔离的命名空间。
- **授权**以 vhost 为边界，分别控制 configure / write / read 三类操作。

#### 直觉建立与边界

可以把 vhost 想成一栋楼，把用户想成持证人，把权限正则想成门禁规则：登录证只能证明“你是谁”，不能自动打开每一扇门。

边界是：权限正则匹配的是资源名；它不是网络防火墙，也不是消息内容过滤器。

#### 核心原理

`set_permissions` 的三个正则依次对应：

```text
configure：能否声明 / 修改对象
write：能否向交换机发布
read：能否从队列消费
```

同一个用户可以对不同 vhost 拥有完全不同的三元组。生产环境应把应用用户限制在自己的 vhost 和资源命名空间内。

#### 示例演示

```bash
# 创建业务 vhost 与业务账号
rabbitmqctl add_vhost /orders
rabbitmqctl add_user app_orders '<从密钥系统注入的密码>'

# 只允许 orders. 前缀资源；三个正则分别是 configure / write / read
rabbitmqctl set_permissions -p /orders app_orders \
  '^orders\\.' '^orders\\.' '^orders\\.'

# 复核，不把密码写进命令历史
rabbitmqctl list_permissions -p /orders
```

#### 常见误区

- **能登录 = 能操作所有队列**：错，登录后仍要过 vhost 和资源权限检查。
- **只收消息的消费者不需要 read 权限**：错，消费就是 read 操作。
- **权限正则能防止消息内容泄露**：错，它只匹配资源名，不检查消息体。

#### 一句话记住

**先认证“你是谁”，再按 vhost 和 configure/write/read 三元组判断“你能做什么”。**

### 知识点 2：客户端 TLS、mTLS 与管理面 HTTPS

#### 一句话定义

TLS 保护连接上的凭据和消息；启用 peer verification 时，客户端还会校验服务端证书。mTLS 再要求客户端出示证书，用证书参与身份认证。

#### 直觉建立与边界

TLS 像给连接套上带验伪封条的信封：它解决窃听与冒充服务端的问题。它不替代 RabbitMQ 的 vhost / 权限模型，也不自动完成账号授权。

#### 核心原理

RabbitMQ 常用端口：`5671` 是 AMQPS，`15671` 是 Management HTTPS；明文端口 `5672` / `15672` 是否保留，应由部署边界和迁移计划决定。

生产配置至少要明确 CA、服务端证书、私钥、peer verification，以及是否要求客户端证书。若采用 mTLS，`fail_if_no_peer_cert = true` 才会把客户端证书变成强制门槛。

#### 示例演示

下面是配置形状，不包含真实证书和私钥；证书文件应由密钥系统或受控挂载提供：

```ini
# rabbitmq.conf：示意配置，落地前先准备证书文件并做回滚方案
listeners.tcp = none
listeners.ssl.default = 5671

ssl_options.cacertfile = /etc/rabbitmq/tls/ca.crt
ssl_options.certfile   = /etc/rabbitmq/tls/server.crt
ssl_options.keyfile    = /etc/rabbitmq/tls/server.key
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = true

management.ssl.port = 15671
management.ssl.cacertfile = /etc/rabbitmq/tls/ca.crt
management.ssl.certfile = /etc/rabbitmq/tls/server.crt
management.ssl.keyfile = /etc/rabbitmq/tls/server.key
```

验证监听器与证书链：

```bash
rabbitmq-diagnostics listeners
openssl s_client -connect broker.example.com:5671 \
  -CAfile ca.crt -servername broker.example.com </dev/null
```

#### 常见误区

- **打开 5671 就等于安全**：错；不校验证书时，仍可能连接到错误的服务端。
- **管理 UI 用 HTTPS，业务 AMQP 就自动是 TLS**：错；两个监听器需要分别配置。
- **mTLS 开启后就不需要 RabbitMQ 用户权限**：错；证书认证和 RabbitMQ 授权仍是两层。

#### 一句话记住

**TLS 先保护连接，vhost 和权限再保护资源；业务端口与管理端口分别验证。**

### 知识点 3：默认账号、凭据轮换与最小权限

生产环境不要依赖默认 `guest` 账号，也不要把管理员账号放进业务服务的环境变量。为每个应用建立独立账号，按服务职责拆分权限，密码由密钥系统注入并可轮换。

```bash
# 上线前检查：不要只看“有用户”，还要看标签和权限
rabbitmqctl list_users
rabbitmqctl list_user_limits
rabbitmqctl list_permissions -p /orders

# 轮换顺序建议：先创建新凭据 → 灰度连接 → 切换流量 → 删除旧凭据
rabbitmqctl add_user app_orders_next '<新密码>'
rabbitmqctl set_permissions -p /orders app_orders_next '^orders\\.' '^orders\\.' '^orders\\.'
```

不要把真实密码写进课程命令、Compose 文件或 shell 历史；本课命令中的尖括号只是密钥注入占位符。

## 第四幕：实操验证

### 验收清单

- [ ] `rabbitmqctl list_users` 中不存在业务服务共用的管理员账号。
- [ ] 业务用户只在目标 vhost 拥有明确的 configure / write / read 权限。
- [ ] `rabbitmq-diagnostics listeners` 能区分 5671 与 15671 的 TLS 监听器。
- [ ] 用正确 CA 验证证书成功；用错误 CA 或错误主机名验证失败。
- [ ] 凭据轮换遵循“新凭据先可用、旧凭据后删除”的顺序。

### 失败时先判断哪一层

```text
登录失败？       → 认证、密码、认证后端
登录成功但拒绝？ → vhost、configure/write/read 正则
握手失败？       → CA、证书 SAN、私钥权限、TLS 版本
管理面能进、业务不能进？ → 15671 与 5671 是两套监听配置
```

## 第五幕：体系收束

本课建立的上线顺序是：

```text
独立账号
  ↓
隔离 vhost
  ↓
最小权限正则
  ↓
TLS / peer verification
  ↓
可轮换凭据 + 可复核监听器
```

### 小测

1. 用户能登录 `/orders`，但发布到 `orders.events` 被拒，优先查什么？
2. 开启 5671 后，为什么还要检查 `ssl_options.verify`？
3. 应用账号需要 `configure` 权限吗？回答时要结合“声明对象”和“只消费已有对象”两种场景。

### 官方文档

- [Access control](https://www.rabbitmq.com/docs/access-control)
- [Virtual hosts](https://www.rabbitmq.com/docs/vhosts)
- [TLS / SSL support](https://www.rabbitmq.com/docs/ssl)
- [Production checklist](https://www.rabbitmq.com/docs/production-checklist)

## 下一课

[课 2《用户、vhost 与权限生命周期》](lesson-02-用户vhost与权限生命周期.md)：把“上线前的安全配置”推进到用户轮换、权限审计和失败排错。
