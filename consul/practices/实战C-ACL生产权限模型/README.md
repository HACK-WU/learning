# 实战篇 C：ACL 生产权限模型落地（配课 8）

> 所属课程：Consul ｜ 配套课：阶段 2 · 课 8《ACL 与安全模型》
> 实战日期：2026-09-17 ｜ 实测环境：Windows 11 + Consul 2.0.2（dev 模式 + ACL）
> **本文所有 HTTP 状态码均为本机真跑结果**，未实测的部分已显式标注

---

## 🎬 第一幕：场景引入

你接手了一套跑了半年的 Consul。三个团队共用一个集群：web 团队、api 团队、数据团队。大家的配置都往同一个 KV 里写，服务注册也没人管权限——因为当初图省事，`acl` 那块配置直接没开。

某天早上，api 团队的配置文件被人改了，数据库连接串指向了一台测试机。查日志发现：改它的请求来自 web 团队一个服务的 IP。

这不是恶意攻击，是有人在调试时手滑写错了前缀——`api/database/host` 打成了 `api/database/host` 之外的某个名字，或者干脆就是复用了一段硬编码路径。**因为没有权限边界，任何能连上 8500 端口的人都能改任何 key。**

问题抛出来：**多团队共用一套 Consul 时，怎么保证"我的东西只有我能改，别人的东西我看得到但动不了"？**

---

## 💥 第二幕：认知冲突

第一反应是：给每个团队发一个 token 不就行了？

```
web 团队 -> token-web
api 团队 -> token-api
```

听起来对，跑起来会撞上三件事：

**第一件：token 本身不携带权限。** Consul 的 token 只是一个身份，权限挂在 **policy** 上，token 通过关联 policy 获得权限。只发 token 不发 policy，等于发了一堆空头名片。

**第二件：`default_policy` 不设成 `deny`，ACL 等于没开。** 默认策略是 `allow` 时，没带 token 的请求照样通行——你精心配的 policy 只约束了"带了 token 的人"，对裸奔的请求毫无作用。

**第三件（最坑）：配错了不报错。** 我在这次实测中写了一条规则：

```hcl
operator_prefix "" {
  policy = "read"
}
```

创建 policy 返回 200，创建 token 返回 200，一切看起来都好。然后拿这个 token 去读 `/v1/operator/raft/configuration`，得到：

```
403 Permission denied: ... lacks permission 'operator:read'
```

**规则写错了，Consul 不告诉你，只是静默地不生效。** 报错原文还只说"缺 operator:read 权限"，让你以为是权限没给够，实际上是给法不对。

正确写法是 `operator = "read"`——因为 `operator` 这个资源**不带 label**。

---

## 🔍 第三幕：层层揭示

### 3.1 三个概念的关系

先用一句话说清 token / policy / rule 三者的关系：

```text
rule   —— 最小单位，形如 key_prefix "web/" { policy = "write" }
policy —— rule 的集合，有个名字，可复用
token  —— 关联一个或多个 policy，是发给应用/人的那串密钥
```

一个 policy 可以被多个 token 关联（比如"只读"策略发给所有值班人员）；一个 token 也可以关联多个 policy（权限叠加）。

> **直觉建立**：policy 是"岗位说明书"，token 是"工牌"。同一个岗位可以发很多工牌，一个人也可以同时兼任两个岗位。

### 3.2 规则语法：哪些带 label，哪些不带

这是本次实测踩到的最大一个坑，值得单独记。

Consul 的 ACL 资源分两类：

| 类型 | 写法 | 资源 |
|------|------|------|
| **带 label**（按名字/前缀划分） | `xxx_prefix "前缀" { policy = "..." }` | `key`、`node`、`service`、`session`、`agent`、`event`、`query` |
| **不带 label**（全局开关） | `xxx = "read"` | `operator`、`acl`、`keyring`、`mesh`、`peering` |

不带 label 的资源**没有 `_prefix` 形式**。写成 `operator_prefix "" { policy = "read" }` 不会报错——HCL 能解析，Consul 也接受——但**权限不生效**。

实测对照（同一个 `/v1/operator/raft/configuration` 接口）：

```text
operator = "read"                            -> 200
operator_prefix "" { policy = "read" }       -> 403   ← 看起来配了，实际没有
operator_prefix "" { policy = "write" }      -> 403   ← 写权限也不隐含读
```

顺带确认另一条：**`write` 在带 label 的资源上是隐含 `read` 的**（`key:write` 能读回自己写的键，实测 200），但在 `operator` 这类不带 label 的资源上，`write` **不隐含** `read`。

### 3.3 三条策略的设计

这次模拟三个角色，策略文件都在 `policies/` 下。

**web 团队**（`pol-team-web.hcl`）——只管自己，能发现别人：

```hcl
key_prefix "web/" {
  policy = "write"
}

key_prefix "shared/" {
  policy = "read"
}

service_prefix "web" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}
```

四个设计点：

1. `key_prefix "web/"` 给 `write`，**不给 `""`**——否则能读全库
2. `service_prefix "web"` 给 `write`，**不给 `""`**——否则能顶掉别人的服务名
3. `service_prefix ""` 给 `read`——让 web 能"发现"别人，但不能"改"别人
4. `node_prefix ""` 给 `read` 是**必需的**——看不到节点就查不到任何健康检查结果

**api 团队**（`pol-team-api.hcl`）——与 web 完全对称，只换前缀。这样设计是为了验证一件事：web 的 token 去动 api 的东西，必须被拒。

**运维值班**（`pol-ops-readonly.hcl`）——排查够用但不能改：

```hcl
key_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

operator = "read"        # ← 注意：不带 label

agent_prefix "" {
  policy = "read"
}
```

---

## 🧪 第四幕：实操验证

### 4.1 起环境

```powershell
# 1) 用本文的 acl-lab.hcl 起一个默认拒绝的 agent
consul agent -dev -config-file=acl-lab.hcl

# 2) 引导出管理 token（整个集群只能做一次，务必保存）
curl -X PUT http://127.0.0.1:8500/v1/acl/bootstrap
# 返回 SecretID，后续操作都带上它
```

### 4.2 建策略与 token

```powershell
# 建策略（Rules 是 HCL 字符串，塞进 JSON）
curl -X PUT http://127.0.0.1:8500/v1/acl/policy `
  -H "X-Consul-Token: <管理token>" `
  -d "{""Name"":""pol-team-web"",""Rules"":""<HCL内容>""}"

# 建 token
curl -X PUT http://127.0.0.1:8500/v1/acl/token `
  -H "X-Consul-Token: <管理token>" `
  -d "{""Description"":""web"",""Policies"":[{""ID"":""<policy-id>""}]}"
```

> 本文 `policies/` 目录下的三个 `.hcl` 文件可直接用，`_setup.py` / `_final_matrix.py` 是完整可跑的自动化脚本。

### 4.3 权限矩阵（21 项全实测）

每个动作都真发一次 HTTP 请求，记录状态码：

| 动作 | web token | api token | ops token | 匿名 |
|------|-----------|-----------|-----------|------|
| 写 `web/db_host` | **200** | 403 | 403 | 403 |
| 写 `api/db_host` | 403 | **200** | 403 | 403 |
| 读 `web/db_host` | 200 | 403 | **200** | 403 |
| 读 `api/db_host` | 403 | 200 | **200** | 403 |
| 递归读 `web/` | **200** | — | 200 | — |
| 递归读 `api/` | **404** ⚠️ | 200 | 200 | — |
| 列所有 keys | `["web/db_host"]` | `["api/db_host"]` | 全可见 | `[]` ⚠️ |
| 注册名为 `web` 的服务 | **200** | 403 | 403 | 403 |
| 注册名为 `api` 的服务 | **403** | 200 | 403 | 403 |
| 注销 `web` 的实例 | **200** | **403** | 403 | 403 |
| 建 session | **403** | — | — | 403 |
| 读 raft 配置 | 403 | — | **200** | 403 |
| 列 token 列表 | 403 | — | **403** | 403 |
| 列服务目录 | 200 | 200 | 200 | **`{}`** ⚠️ |
| 查健康实例 | 200 | 200 | 200 | **`[]`** ⚠️ |

**逐条解读三个"看起来正常其实不正常"的格子：**

**① 递归读别人的前缀返回 404，不是 403**

```text
web 单键读 api/db_host        -> 403  （明确：没权限）
web 递归读 api/  ?recurse=true -> 404  （看起来：没数据）
```

`api/db_host` 明明存在（ops 用同样方式读返回 200）。**同一个权限问题，单键读和递归读给出两种表现。** 递归查询把"无权限"降级成了"不存在"。

**② 匿名访问列目录/列 keys 返回 200 空结果**

```text
匿名列服务目录    -> 200 {}
匿名列 keys      -> 200 []
匿名查健康实例    -> 200 []
```

这三个 `200` 最容易骗人。它们看起来像"集群里没数据"，实际是"你没权限看"。课 8 已把这类列为**最危险的静默失败**——比报错更糟，因为它不会触发任何告警。

**③ `session:write` 没给就建不了 session**

web 团队策略里没有 `session_prefix`，导致建 session 直接 403。这意味着**分布式锁用不了**——课 6 讲的 session + KV 锁方案，在开了 ACL 之后需要额外补一条 `session_prefix` 规则。这是 ACL 上线时最容易漏的一项。

### 4.4 阻塞查询的静默失效（重点）

把上面 ①②两条合起来看，会得到一个很实际的后果。

配置热更新的标准做法（课 6、以及本课程的实战项目）是**阻塞查询**：

```
GET /v1/kv/api/?recurse=true&index=<上次的index>&wait=5m
```

如果跑这个查询的 token 对 `api/` 没有读权限，实测返回：

```text
404（空 body）
```

客户端代码通常是这么写的：

```python
try:
    result = kv_get(prefix, recurse=True, index=last_index, wait='5m')
except ConsulError as e:
    if e.status == 404:
        # 前缀不存在 = 还没有配置，属正常初始状态
        return {}
    raise
```

于是"没权限"被当成了"还没配"，**配置热更新静默失效，而且没有任何报错**。服务会一直用启动时的旧配置跑下去，直到有人发现配置没生效。

**这是本次实测最有价值的一条结论**：ACL 上线后，如果某个服务的配置突然不更新了，先查它 token 的 `key_prefix` 权限——而不是去查 Consul 的 watch 机制。

---

## 🎯 第五幕：体系收束

### 5.1 最小权限策略的四条写法

1. **按前缀切，不用 `""` 全开**——`key_prefix "web/"` 而不是 `key_prefix ""`
2. **读发现、写自己**——`service_prefix ""` 给 `read` + `service_prefix "web"` 给 `write`
3. **`node_prefix ""` 给 `read` 是必需的**，漏了连健康检查结果都看不到
4. **不带 label 的资源用 `xxx = "read"` 写法**——`operator`、`acl`、`keyring`、`mesh`、`peering`

### 5.2 ACL 上线检查清单

| # | 检查项 | 本次实测证据 |
|---|--------|-------------|
| 1 | `default_policy = "deny"` 已设 | 匿名注册服务 403 |
| 2 | 每个团队只拿到自己的写权限 | web 写 `api/` 403 |
| 3 | 值班账号不能改业务数据 | ops 写 `web/` 403 |
| 4 | 不带 label 的资源写法正确 | `operator = "read"` 生效（raft 配置 200） |
| 5 | 需要锁的服务补了 `session_prefix` | 未补 → 建 session 403 |
| 6 | 配置热更新链路验证过（不只看 200） | 越权递归读返回 404，会静默失效 |
| 7 | 管理 token 已离线保存 | bootstrap 只能执行一次 |

### 5.3 一句话记住

> **ACL 的难点不在"配权限"，在于"配错了它不告诉你"**——把 404 当成"没数据"、把 200 空结果当成"集群是空的"，是 ACL 上线后最常见的两类误判。

---

## 📋 本课速览

| 项 | 内容 |
|----|------|
| 一句话定义 | ACL = token（身份）+ policy（权限集合）+ rule（具体规则）三层 |
| 关键语法 | `operator`/`acl`/`keyring`/`mesh`/`peering` **不带 label**，写 `operator = "read"` |
| 最危险的静默失败 | 递归读无权限返回 **404**；匿名列目录返回 **200 空** |
| 必给的权限 | `node_prefix ""` read（否则查不到健康状态） |
| 最易漏的权限 | `session_prefix`（否则分布式锁用不了） |
| 上线必查 | 配置热更新链路——不只看有没有 200，要看返回的到底是不是预期数据 |

---

## 🧭 课程导航

- 配套课：[lesson-08 ACL 与安全模型](../../stages/2-核心能力拆解/lessons/lesson-08-ACL与安全模型.md)
- 前置：[lesson-06 KV 存储与配置管理](../../stages/2-核心能力拆解/lessons/lesson-06-KV存储与配置管理.md)（阻塞查询与 session 锁）
- 相关排障：[09-排障速查手册.md](../../09-排障速查手册.md) 症状 10「ACL 静默失败」
- 正向指引：[10-场景解法库.md](../../10-场景解法库.md) 场景 8「生产权限收口」
- 判定依据：[应用实战篇-逐课判定.md](../../应用实战篇-逐课判定.md)

---

## ✅ 小测（4 题）

**1. 下面哪条规则能让 token 读到 `/v1/operator/raft/configuration`？**

A. `operator_prefix "" { policy = "read" }`
B. `operator = "read"`
C. `operator_prefix "" { policy = "write" }`
D. `node_prefix "" { policy = "read" }`

<details><summary>答案</summary>

**B**。`operator` 是不带 label 的资源，只有 `operator = "read"` 这种写法生效。A 和 C 都不会报错但**权限静默不生效**——这是本次实测踩到的坑。D 与 operator 接口无关。

</details>

**2. web 团队的 token 对 `api/` 前缀没有读权限，它发起 `GET /v1/kv/api/?recurse=true` 会得到什么？**

A. 403
B. 404
C. 200 空数组
D. 200 带数据

<details><summary>答案</summary>

**B. 404**。这是本次实测的关键发现：递归查询把"无权限"降级成"不存在"，与单键读的 403 表现不同。后果是配置热更新的阻塞查询会**静默失效**。

</details>

**3. 匿名请求列服务目录返回 `200 {}`，这说明什么？**

A. 集群里没有服务
B. 匿名有读权限，只是恰好没数据
C. 匿名没权限，但 Consul 返回空结果而非报错
D. ACL 未启用

<details><summary>答案</summary>

**C**。课 8 与本次实测都确认了这一行为：匿名列目录/列 keys/查健康实例都返回 `200` 空结果。看起来像"没数据"，实际是"没权限"——这是最危险的静默失败类型。

</details>

**4. 一个服务要在开了 ACL 的集群上用 session + KV 锁做领导者选举，它的 policy 必须包含什么？**

A. 只要有 `key_prefix` write 就够了
B. 必须额外有 `session_prefix` 写权限
C. 必须额外有 `operator = "write"`
D. 必须额外有 `acl = "read"`

<details><summary>答案</summary>

**B**。本次实测中，web 团队的策略没有 `session_prefix`，建 session 直接 403——分布式锁用不了。这是 ACL 上线时最容易漏的一项。

</details>

---

## 🔖 接力提示词

> 下一篇建议做**实战篇 A：一致性读模式实测**（配课 5）。本篇解决"谁能动什么"，下一篇解决"读到的东西有多新"——一个是权限边界，一个是新鲜度边界，都是生产落地绕不开的。
>
> 复制这句给 AI：
> 「按 `应用实战篇-逐课判定.md` 的立项说明，写实战篇 A（课 5 三种读模式实测），体例与实战篇 C 一致。」

---

## 📎 评审结论（双视角，对学员可见）

**A 视角 · 技术事实核查**

| 核查项 | 结论 |
|--------|------|
| 全部 HTTP 状态码 | ✅ 21 项矩阵 + 8 项边界补测，均为本机 Consul 2.0.2 真跑 |
| `operator` 不带 label 的说法 | ✅ 实测三种写法对照（200/403/403），并联网核实[官方 ACL rule 参考](https://developer.hashicorp.com/consul/docs/reference/acl/rule)确认"operator 资源不带 label" |
| 递归读 404 与单键读 403 的差异 | ✅ 同一环境下对同一键做了两种读法对照 |
| 匿名三类 200 空结果 | ✅ 与课 8 既有结论一致，本次复现确认 |
| `session:write` 缺失导致锁不可用 | ✅ 建 session 实测 403 |
| `write` 是否隐含 `read` | ✅ 带 label 资源隐含（key:write 可读回），`operator` 不隐含（实测 403） |

**B 视角 · 零基础教学体验**

- 三个角色（web/api/ops）对称设计，越权对照一目了然，不需要脑补
- 语法坑放在第二幕"认知冲突"而不是附录——因为这是读者最可能踩、且踩了最难查的点
- 4.4 节把"递归读 404"和"热更新失效"串成一条因果链，从现象推到业务后果
- 表格中三个 ⚠️ 标记专门标注"看起来正常其实不正常"的格子，避免读者照抄时误判

**仍存在的已知边界**

1. 本次跑在 **dev 单节点**上。多节点场景下，token 需要 ACL 复制（`/v1/acl/replication`），本文未涉及
2. `down_policy = "extend-cache"` 的实际行为（ACL 数据中心不可用时的兜底）本次**未实测**，仅按官方文档说明写入注释
3. 企业版的 namespace / admin partition 未提供（本机为社区版）
4. token 撤销后的生效时延**未实测**——本文不做相关断言
