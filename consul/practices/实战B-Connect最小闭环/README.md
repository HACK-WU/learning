# 实战篇 B：Connect 服务网格最小闭环（配课 7）

> 所属课程：Consul ｜ 配套课：阶段 2 · 课 7《多数据中心与服务网格》
> 实战日期：2026-09-17 ｜ 实测环境：Windows 11 + Consul 2.0.2（dev 模式）
> **本文 mTLS 数据面已真跑通**，未实测的部分已显式标注

---

## 🎬 第一幕：场景引入

你的服务间调用现在是明文 HTTP。安全评审提了一条：服务之间的流量必须加密，且要有身份认证——不能随便哪个进程都能调你的内部接口。

两个选项摆在你面前：

**选项一**：每个服务自己接 TLS，自己管证书。要做的事包括：建私有 CA、给每个服务签发证书、写证书轮转逻辑（证书会过期）、处理吊销、在每个服务的代码里配置 TLS……而且每加一个新服务，这套流程要重来一遍。

**选项二**：用 Consul Connect。应用代码**一行都不改**，sidecar 代理替它完成加密和身份认证。

本文实测选项二，并回答一个关键问题：**不装 Envoy 能不能跑通？**

---

## 💥 第二幕：认知冲突

先泼一盆冷水：课 7 的判定文件里写着——

> 本课 Connect 实操此前受环境限制（无 Envoy sidecar 二进制）

我这次实测前先查了一遍环境：

```text
envoy              -> NOT FOUND
consul-dataplane   -> NOT FOUND
```

两个都没有。看起来这条路走不通了。

**但是**，`consul connect --help` 里有一行：

```
proxy    Runs a Consul Connect proxy
```

Consul 自带一个**内置代理**（built-in proxy）。它功能比 Envoy 少——没有七层路由、没有灰度、没有高级负载均衡——但它**能跑 mTLS**。

关键区别在于：

| | 内置代理 | Envoy |
|---|---|---|
| mTLS 加密与身份认证 | ✅ | ✅ |
| 四层（L4）授权 | ✅ | ✅ |
| 七层（HTTP 路径/方法）授权 | ❌ | ✅ |
| 灰度发布 / 流量拆分 | ❌ | ✅ |
| 可观测性指标丰富度 | 基础 | 丰富 |

**如果你的目标只是"服务间流量加密 + 谁可以调谁"，内置代理就够了，不用装 Envoy。** 只有需要七层能力时才得上 Envoy。

这个区分很重要——很多人以为"用不了 Envoy 就没法用 Connect"，于是在"全量上 Envoy"和"完全不用网格"之间二选一，忽略了中间这一档。

---

## 🔍 第三幕：层层揭示

### 3.1 Connect 的三个零件

```text
1. 内置 CA     —— 签发证书，dev 模式自动初始化
2. sidecar     —— 每个服务旁边跑的代理，代它收发流量
3. intention   —— 授权规则："允许谁访问谁"
```

**一句话定义**：Connect 是一个基于 mTLS 的服务间通信层，身份由证书承载，授权由 intention 控制，应用本身不需要感知。

> **直觉建立**：sidecar 像是给每个服务配了个"加密电话机"。服务 A 想打给服务 B，它拨的是本地分机号（local_bind_port），电话机自动加密、自动表明身份、自动检查"这个号码允许打吗"，然后才接通。

### 3.2 身份从哪来：SPIFFE ID

每个服务的身份不是 IP，不是端口，而是一个 **SPIFFE ID**。本次实测抓到的真实值：

```text
spiffe://36c84f4a-1282-356d-be10-3271104b8b8d.consul/ns/default/dc/dc1/svc/web
spiffe://36c84f4a-1282-356d-be10-3271104b8b8d.consul/ns/default/dc/dc1/svc/api
```

拆开看：

```text
spiffe://<trust-domain>/ns/<命名空间>/dc/<数据中心>/svc/<服务名>
```

**为什么不用 IP 做身份**：IP 会变（容器重启、扩缩容），而且可以被伪造。SPIFFE ID 由证书携带、由 CA 签名，伪造不了。

### 3.3 证书的有效期分层

本次实测读到的真实数据：

| 证书 | 有效期 | 实测值 |
|------|--------|--------|
| 根证书（CA） | **10 年** | `2026-09-17` → `2036-09-14` |
| 叶子证书（leaf，服务用） | **3 天** | `2026-09-17T07:33:28Z` → `2026-09-20T07:33:28Z` |

为什么要这么设计？**根证书长期有效，因为换根成本高**（所有服务都要信任新根）；**叶子证书短期有效，因为泄露影响小**（三天后自动作废）。轮转由 Consul 自动完成，应用无感。

### 3.4 流量是怎么走的

本次实测的拓扑：

```text
调用方 ──> 127.0.0.1:21002 (web 的 sidecar upstream 监听)
              │
              │  mTLS（双向证书认证）
              ▼
          127.0.0.1:21000 (api 的 sidecar public listener)
              │
              │  明文 localhost
              ▼
          127.0.0.1:9090  (api 真实进程)
```

注意最后一跳是**明文**。sidecar 和真实服务在同一台机器上走 localhost，这一段不加密——这也引出一个重要边界，见 4.5。

---

## 🧪 第四幕：实操验证

### 4.1 起环境

```powershell
# 1) 起 dev agent（dev 模式会自动初始化内置 CA）
consul agent -dev

# 2) 注册两个带 sidecar 的服务
consul services register api.json
consul services register web.json
```

注册完查一下，sidecar 是**自动注册**的：

```text
api-1                 port=9090    kind=
api-1-sidecar-proxy   port=21000   kind=connect-proxy   ← 自动出现
web-1                 port=8080    kind=
web-1-sidecar-proxy   port=21001   kind=connect-proxy   ← 自动出现
```

**你只注册了服务，sidecar 是 Consul 补的。** 这就是 `connect: { sidecar_service: {} }` 这个空对象的作用。

### 4.2 一个必踩的坑：upstream 端口不能与 sidecar 端口相同

我第一次配 web 的 upstream 用 `21001`，结果：

```
[ERROR] proxy: listener stopped with error:
        listen tcp 127.0.0.1:21001: bind: Only one usage of each socket address
```

因为 web 的 sidecar 自己已经占了 21001。改成 `21002` 后正常：

```
[INFO] proxy: Starting listener: listener=127.0.0.1:21002->service:default/default/api
[INFO] proxy: Proxy loaded config and ready to serve
```

**sidecar 的默认端口从 21000 开始递增**，配 upstream 时要避开。

### 4.3 启动代理并跑通 mTLS

```powershell
# 终端 A：api 的 sidecar（入站）
consul connect proxy -sidecar-for api-1

# 终端 B：web 的 sidecar（出站）
consul connect proxy -sidecar-for web-1

# 终端 C：api 真实后端
python backend.py 9090 api
```

然后通过 web 的 upstream 端口访问：

```powershell
Invoke-WebRequest http://127.0.0.1:21002/
```

实测结果：

```text
HTTP 200
{"service": "api", "path": "/", "message": "hello from api"}
```

**mTLS 数据面跑通了，全程没装 Envoy。** 请求从 21002 进，经过双向证书认证，到达 api 进程再返回。

### 4.4 验证"加密"真的是加密：不带证书会被拒

跑通了不代表加密了。做个对照实验——**不带客户端证书直接连 api 的 sidecar**：

```python
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
with socket.create_connection(('127.0.0.1', 21000), timeout=5) as sock:
    with ctx.wrap_socket(sock) as ssock:   # ← 这里失败
        ...
```

实测报错：

```text
SSLError: [SSL: TLSV13_ALERT_CERTIFICATE_REQUIRED] tlsv13 alert certificate required
```

**服务端主动要求客户端出示证书**（`certificate required`）。不是"允许匿名但记录日志"，是**直接拒绝**。这才是 mTLS 该有的行为。

### 4.5 关键边界：绕过 sidecar 直连后端是明文

这一条必须写清楚，否则会给人虚假的安全感。

```text
直连 127.0.0.1:9090（api 真实端口，绕过 sidecar）
→ HTTP/1.0 200 OK
```

**明文连上了，没有任何阻拦。**

原因见 3.4 的拓扑图：sidecar 和真实服务之间走的是 localhost 明文。Consul 能管的是"进 sidecar 的流量"，管不了"绕过 sidecar 直达应用端口的流量"。

所以 Connect 的安全边界依赖于：**应用端口不能被绕过**。生产上靠三件事保证：

1. 应用只监听 `127.0.0.1`（不监听 `0.0.0.0`），外部进不来
2. 网络策略（防火墙 / NetworkPolicy）限制端口访问
3. 容器环境下 sidecar 与应用同 Pod，共享网络命名空间

**如果应用监听在 `0.0.0.0` 且没有网络策略，任何人都能绕过 mTLS 直连它——网格等于白建。** 这是本次实测最有警示意义的一条。

### 4.6 intention 授权：从 allow 到 deny

先确认默认状态（没有 intention 时）能通：

```text
默认 -> HTTP 200 {"service": "api", ...}
```

写入 deny 规则（注意 Consul 1.9+ 用 `service-intentions` 配置条目）：

```json
{
  "Kind": "service-intentions",
  "Name": "api",
  "Sources": [
    { "Name": "web", "Action": "deny" }
  ]
}
```

```powershell
consul config write intention-deny.json
```

**立刻**再访问：

```text
ERR: 基础连接已经关闭: 连接被意外关闭。
```

看 api sidecar 的日志，有明确的拒绝原因：

```text
[ERROR] proxy.connect: authz call denied: service=api
        reason="Matched L4 intention: default/web => default/api (Precedence: 9, Action: DENY)"
```

三个信息量：**匹配了哪条规则**（web → api）、**优先级**（Precedence 9）、**动作**（DENY）。

### 4.7 恢复时延实测：与课 7 记录不同

改回 allow：

```text
第 1 次（+82ms）-> HTTP 200 已恢复
```

**82 毫秒内恢复。**

这里要说明一件事：课 7 曾记录过"删除 intention 后 11 分钟仍返回已删意图""新意图 60 秒观察窗内未生效"的现象。本次实测**没有复现**——deny 与 allow 都是秒级生效。

差异可能来自：本次用的是 `consul config write`（配置条目），课 7 用的是旧版 `/v1/connect/intentions` API；或者是版本行为有变化（本次为 2.0.2）。

**本文按实测结果记录：2.0.2 + 配置条目方式下，intention 变更秒级生效。** 课 7 记录的现象作为历史观察保留，但不在本文重复断言。

---

## 🎯 第五幕：体系收束

### 5.1 Connect 的三个认知要点

1. **应用零改动**——加密与认证由 sidecar 承担，代码里不出现 TLS 相关的一行
2. **身份是 SPIFFE ID，不是 IP**——证书携带、CA 签名，扩缩容与重启都不影响
3. **授权是 intention，与加密解耦**——加密管"路上安全"，intention 管"你有没有资格访问"

### 5.2 内置代理 vs Envoy 的选型判断

| 你的需求 | 选择 |
|---------|------|
| 只要服务间加密 + 身份认证 | **内置代理**，零依赖 |
| 需要按 HTTP 路径/方法授权 | Envoy |
| 需要灰度发布、流量拆分 | Envoy |
| 需要丰富的网格指标 | Envoy |
| 先验证可行性，再决定投入 | **先用内置代理跑通，再评估是否值得上 Envoy** |

### 5.3 上 Connect 前必须确认的三件事

| # | 检查项 | 本次实测证据 |
|---|--------|-------------|
| 1 | 应用只监听 `127.0.0.1` | 监听 `0.0.0.0` 时绕过 sidecar 可明文直连（4.5） |
| 2 | upstream 端口避开 sidecar 端口段 | 撞端口会 `bind: Only one usage...`（4.2） |
| 3 | 不需要七层能力 | 内置代理只做 L4，路径级授权做不到 |

### 5.4 一句话记住

> **Connect 加密的是"进 sidecar 的流量"，不是"应用的端口"**——应用监听 `0.0.0.0` 又没有网络策略时，mTLS 可以被一步绕过。

---

## 📋 本课速览

| 项 | 内容 |
|----|------|
| 一句话定义 | Connect = 内置 CA 签发证书 + sidecar 代收发 + intention 控授权，应用零改动 |
| 不装 Envoy 能跑吗 | ✅ 能。内置 `consul connect proxy` 支持 mTLS，但只有 L4 能力 |
| 身份形式 | SPIFFE ID：`spiffe://<trust-domain>/ns/default/dc/dc1/svc/<服务名>` |
| 证书有效期 | 根证书 10 年，叶子证书 **3 天**（自动轮转） |
| 无证书访问 | TLS 握手即失败：`TLSV13_ALERT_CERTIFICATE_REQUIRED` |
| 最大边界 | 绕过 sidecar 直连应用端口 = 明文，网格失效 |
| intention 生效时延 | 本次实测 **82ms**（2.0.2 + 配置条目方式） |

---

## 🧭 课程导航

- 配套课：[lesson-07 多数据中心与服务网格](../../stages/2-核心能力拆解/lessons/lesson-07-多数据中心与服务网格.md)
- 相关实战：[实战篇 C：ACL 生产权限模型](../实战C-ACL生产权限模型/README.md)（控制面权限 vs 数据面授权）
- 相关排障：[09-排障速查手册.md](../../09-排障速查手册.md)
- 正向指引：[10-场景解法库.md](../../10-场景解法库.md) 场景 7「mTLS 授权」
- 判定依据：[应用实战篇-逐课判定.md](../../应用实战篇-逐课判定.md)

---

## ✅ 小测（4 题）

**1. 本机没有 Envoy 二进制，能跑通 Consul Connect 的 mTLS 吗？**

A. 不能，Connect 强依赖 Envoy
B. 能，Consul 有内置代理，支持 mTLS 与 L4 授权
C. 能，但只能加密，做不了任何授权
D. 不能，必须装 consul-dataplane

<details><summary>答案</summary>

**B**。实测用 `consul connect proxy -sidecar-for <id>` 跑通了完整 mTLS，intention 的 deny 也正常生效。内置代理的限制是**只做 L4**（没有七层路径授权、没有灰度），不是"做不了授权"。

</details>

**2. 攻击者绕过 sidecar，直连应用的真实端口，会发生什么？**

A. 被 sidecar 拦截
B. 明文连通，mTLS 保护失效
C. 需要证书才能连
D. 会被 intention 拒绝

<details><summary>答案</summary>

**B**。实测直连 `127.0.0.1:9090` 返回 `HTTP/1.0 200 OK`。sidecar 管的是"进 sidecar 的流量"，应用端口如果暴露在 `0.0.0.0` 且无网络策略，网格等于白建。

</details>

**3. 配置 upstream 的 `local_bind_port` 时要注意什么？**

A. 必须大于 1024
B. 不能与 sidecar 自身端口冲突（sidecar 默认从 21000 递增）
C. 必须与目标服务端口一致
D. 必须小于 21000

<details><summary>答案</summary>

**B**。实测把 upstream 配成 21001（web sidecar 自己的端口）时报 `bind: Only one usage of each socket address`。改成 21002 后正常。

</details>

**4. 关于证书有效期，下列说法正确的是？**

A. 根证书和叶子证书都是 3 天
B. 根证书 10 年，叶子证书 3 天
C. 根证书 3 天，叶子证书 10 年
D. 两者都是 10 年

<details><summary>答案</summary>

**B**。实测根证书 `2026-09-17` → `2036-09-14`（10 年），叶子证书 `2026-09-17` → `2026-09-20`（3 天）。根长期是因为换根成本高；叶子短期是因为泄露影响小，且自动轮转。

</details>

---

## 🔖 接力提示词

> 三份实战篇已全部完成。建议回到 [应用实战篇-逐课判定.md](../../应用实战篇-逐课判定.md) 把状态从"判定完成、正文待写"更新为"已完成"，并把三篇链接登记进 [02-课程目录.md](../../02-课程目录.md)。
>
> 复制这句给 AI：
> 「三份实战篇正文已完成，回写逐课判定文件的状态与课程目录索引。」

---

## 📎 评审结论（双视角，对学员可见）

**A 视角 · 技术事实核查**

| 核查项 | 结论 |
|--------|------|
| mTLS 数据面是否真跑通 | ✅ 通过 upstream 21002 访问返回 HTTP 200，body 为后端真实响应 |
| 无证书访问是否被拒 | ✅ `TLSV13_ALERT_CERTIFICATE_REQUIRED`，握手阶段即失败 |
| 绕过 sidecar 直连 | ✅ 明文 200（已作为边界写入正文，非缺陷） |
| intention deny 生效 | ✅ 连接被切断，日志含 `Matched L4 intention ... Action: DENY` |
| intention 恢复时延 | ✅ 实测 82ms（2.0.2 + `consul config write`） |
| 证书有效期 | ✅ 根 10 年 / 叶 3 天，取自 `/v1/connect/ca/roots` 与 `/v1/agent/connect/ca/leaf/api` |
| SPIFFE ID | ✅ 从两个 proxy 日志与 leaf 接口三处交叉确认 |
| 与课 7 的"幽灵意图"差异 | ⚠️ **本次未复现**，已在正文显式说明差异可能来源，未重复断言 |

**B 视角 · 零基础教学体验**

- 第二幕直接回应"没装 Envoy 怎么办"这个真实障碍，而不是假设环境齐全
- 内置代理 vs Envoy 的对照表放在认知冲突处，让读者先建立"有中间档"的认知
- 4.5 节把"绕过 sidecar 是明文"单列，配拓扑图说明为什么——这是最容易产生虚假安全感的地方
- intention 时延一节主动指出与课 7 记录的冲突并说明可能原因，避免读者在不同文档间困惑

**仍存在的已知边界**

1. 本次**未装 Envoy**，七层能力（路径级授权、灰度、流量拆分）**未实测**，正文相关表述基于官方文档，未做实测断言
2. 内置代理多节点场景下的行为**未实测**（本次为 dev 单节点 + 两个本地 sidecar）
3. `consul-dataplane`（新版推荐的数据面）未安装，与内置代理的差异**未对比**
4. intention 的 Precedence 优先级体系（多规则冲突时的裁决）**只观察到 Precedence 9 这一个值**，未做多规则冲突实测
5. 证书轮转过程（3 天后自动换新）**未实测**——需要等待或改系统时间，本次未做
