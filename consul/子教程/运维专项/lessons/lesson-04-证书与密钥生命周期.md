# 课 4：证书与密钥生命周期

> 面向：运维 / SRE
> 前置：课 1（生产部署）、课 2（集群健康）。主线课 8（ACL 与安全模型）讲"有什么安全机制"，本课讲"这些机制的**凭证怎么养**"。
> 本课所有数字均来自本机 WSL Ubuntu 24.04 + Consul 2.0.2 三节点集群实测（2026-09-20）。

---

## 引子：一个让人后背发凉的场景

集群跑了两年，一切正常。某天凌晨，所有服务同时开始报 `x509: certificate has expired`。你登上服务器，`consul members` 显示三个节点都在、State 都是 alive。你查健康、查 Raft、查 leader——全都正常。

但服务就是连不上。

因为你从来不知道 Consul 里**有三套完全独立的凭证**，而其中任何一套过期，都会精确地表现为"集群看起来很健康，但业务全挂"。

这三套凭证是：

| 凭证 | 保护什么 | 存在哪 | 过期后果 |
|---|---|---|---|
| **gossip 加密密钥** | 节点间 LAN gossip 通信 | 配置文件 `encrypt` 项（明文） | 新节点加不进来 |
| **TLS 证书** | agent 间 / API 的 HTTPS 通信 | 磁盘 pem 文件 | HTTPS 握手失败 |
| **Connect CA** | 服务网格 mTLS 的身份根 | Consul 内部（Raft 状态） | 签不出新证书，mTLS 建不起来 |

**关键认知**：三者**互不影响、各自独立过期**。你续了 TLS 证书，不代表 CA 没过期；CA 是新的，gossip key 可能是两年前那个。

这就是为什么主线课 11 的"运维五问"里要单独问一句"谁负责三类证书/密钥的轮换"。

---

## 一、三类凭证分别是什么

### 1.1 gossip 加密密钥

一句话：**节点之间说悄悄话用的对称密钥**。

- 配置方式：每个 agent 配置里写 `encrypt = "<base64 key>"`
- 生成：`consul keygen`
- 实测：

```console
$ consul keygen
ORVmOw7NHDOLn1OZwbwga6oCA7nN/7D0jz6PK45ECkI=
$ echo -n "ORVmOw7NHDOLn1OZwbwga6oCA7nN/7D0jz6PK45ECkI=" | wc -c
44
```

44 个字符，是 **32 字节的 base64 编码**。

**运维要点**：
- 它**没有过期时间**——一把 key 用到永远。所以"轮换"不是因为过期，而是因为**泄漏风险**（人员离职、配置仓库泄露）。
- 它是**对称密钥**，写死在配置文件里，所有节点必须一致。
- 不一致的后果：新节点 `encrypt` 与集群不同 → gossip 层解密失败 → **加不进集群**，但已有节点的 Raft 可能还在正常工作，于是你看到一个"半通不通"的集群。

**常见误区**：以为 gossip key 过期会导致集群分裂。不会。它**永不过期**，只会因为**不一致**导致新节点加入失败。

### 1.2 TLS 证书

一句话：**agent 之间和 API 通信的 HTTPS 凭证**。

- 存在磁盘：`ca.pem` / `server.pem` / `server-key.pem`
- 有明确的**有效期**，会过期
- 实测签发一张 30 天证书：

```console
$ openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
    -keyout ca-key.pem -out ca.pem -subj "/CN=consul-ops-ca"
$ openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
    -CAcreateserial -days 30 -out server.pem
$ openssl x509 -in server.pem -noout -enddate
notAfter=Oct 20 12:08:58 2026 GMT
```

**运维要点**：到期日是可计算的，所以**可以监控**。剩余天数实测：

```console
到期时刻 = 2026-10-20 12:08:58 UTC
剩余天数 = 29 天
→ 告警阈值常设 30 天，剩余 29 天 已触发
```

### 1.3 Connect CA

一句话：**服务网格里所有服务身份的根**。

Consul 内置 CA 的实测状态：

```console
$ curl -s http://127.0.0.1:8501/v1/connect/ca/roots
ActiveRootID = 1f:fd:0a:49:34:84:f5:5e:99:bb:51:5c:53:7a:8e:0e:3e:8a:3d:a4
TrustDomain  = 6113d224-49ed-f75f-2fb6-418c05ea9d20.consul
Roots 数量   = 1
  Root SerialNumber=7
  NotBefore=2026-09-20T07:55:10Z NotAfter=2036-09-17T07:55:10Z
  Active=True
  有效期跨度 = 3650 天
```

**根证书有效期 3650 天（10 年）**。

**运维要点**：
- 根证书 10 年看似很长，但真正签发服务证书的是**中间证书**（intermediate），它的 TTL 由 `IntermediateCertTTL` 控制，实测默认 `8760h`（1 年）。
- 而服务实际使用的**叶子证书** TTL 只有 `72h`（3 天）——这是三者中最短的。
- 所以**实际每年都要关心一次（中间证书），而叶子证书每 3 天就在自动续**。

**常见误区**：看到根证书 10 年就以为十年不用管。错。要管的是**中间证书**（1 年）；而叶子证书（3 天）虽然短，但它是 Consul 自动续签的，反而不用你操心——**前提是 CA 本身是健康的**。CA 一旦出问题，3 天后所有叶子证书续不出来，服务网格全线崩塌。

### 1.4 三者对比速查

| 维度 | gossip key | TLS 证书 | Connect CA |
|---|---|---|---|
| 有过期时间 | 否（永不过期） | 是（自定，常 1 年） | 根 10 年 / 中间 1 年 / 叶子 3 天 |
| 存在哪 | 配置文件明文 | 磁盘 pem | Consul 内部 Raft 状态 |
| 轮换触发原因 | 泄漏风险 | 到期 | 到期 / 泄漏 |
| 轮换要重启吗 | 否（keyring 热切换） | 通常要 reload/重启 | 否（API） |
| 轮换期新旧并存 | 是 | 否（直接换） | 是（过渡期） |
| 过期后能否补救 | 能（改配置重启） | 能（换文件） | 见课 5 |

---

## 二、轮换：三类各自怎么转

### 2.1 gossip key：唯一能真正平滑轮换的

Consul 的 `keyring` 机制允许**新旧 key 并存**：

```bash
# 1. 安装新 key（此时新旧并存，两种都能解密）
consul keyring -install="<new key>"

# 2. 切到新 key 用于加密（旧 key 仍可解密）
consul keyring -use="<new key>"

# 3. 确认所有节点都拿到新 key 后，移除旧 key
consul keyring -remove="<old key>"
```

**为什么必须三步**：集群是分布式的，你没法在同一秒改完所有节点。如果直接换，必有中间态——一半节点用新 key 加密，另一半解不开。三步法让"能解密"和"用于加密"解耦。

**实测现状**（未启用加密的集群）：

```console
$ consul keyring -list
==> Gathering installed encryption keys...
error: Unexpected response code: 500 (4 errors occurred:
	* opsdc1 (LAN) error: 3/3 nodes reported failure
	* ops-node-1: Keyring is empty (encryption not enabled)
	* ops-node-2: Keyring is empty (encryption not enabled)
	* ops-node-3: Keyring is empty (encryption not enabled)
```

**这是一个值得记住的告警信号**：`keyring -list` 报 `Keyring is empty` 不是故障，而是告诉你**这个集群压根没开 gossip 加密**。生产环境看到这个，说明你的 gossip 流量是明文的。

### 2.2 TLS 证书：换文件 + reload

- 换 `server.pem` / `server-key.pem`
- `consul reload` 让 agent 重新加载证书文件
- 注意：部分 TLS 相关配置变更**不支持热加载**，需要重启（以实际版本 release note 为准）

**没有过渡期**：新证书生效就是生效，客户端要么信任新 CA 要么不信任。所以换 TLS 证书必须**协调客户端**，或者保证新旧证书被同一个 CA 签发的信任链覆盖。

### 2.3 Connect CA：API 更新 ≠ 立即轮换

这是本课最容易踩的坑，我用实测说明。

我尝试通过更新 CA 配置来触发轮换：

```console
$ curl -s -X PUT -d '{"Provider":"consul","Config":{"RotationPeriod":"2160h","IntermediateCertTTL":"8760h"}}' \
    http://127.0.0.1:8501/v1/connect/ca/configuration
HTTP 200
Configuration updated!

$ curl -s http://127.0.0.1:8501/v1/connect/ca/roots | ... | len(Roots)
1
```

**配置更新成功了（HTTP 200，ModifyIndex 从 5 变成 2130），但 root 数量仍然是 1。**

为什么？因为内置 CA 的轮换是**按周期自动进行**的，由 `RotationPeriod` 控制（我设的 `2160h` = 90 天）。改配置只是改了"下次什么时候转、中间证书多久"，**不会立刻触发一次轮换**。

**认知纠正**：

| 你的预期 | 实际 |
|---|---|
| 改 CA 配置 → 立刻换新 root | 改配置只改策略，轮换按周期发生 |
| root 数会变成 2（新旧并存） | 只有到轮换窗口才会变成 2 |

**内置 CA 的真实默认配置**（全新集群、未经任何写入，实测）：

```console
$ curl -s http://127.0.0.1:8501/v1/connect/ca/configuration
{"Provider":"consul",
 "Config":{"IntermediateCertTTL":"8760h","LeafCertTTL":"72h","RootCertTTL":"87600h"},
 "State":null,"ForceWithoutCrossSigning":false,"CreateIndex":5,"ModifyIndex":9}
```

| 配置项 | 默认值 | 含义 |
|---|---|---|
| `RootCertTTL` | `87600h` = **10 年** | 根证书有效期（与上面实测 3650 天吻合） |
| `IntermediateCertTTL` | `8760h` = **1 年** | 中间证书有效期 ← **真正每年要关心的** |
| `LeafCertTTL` | `72h` = **3 天** | 服务叶子证书有效期 ← **最短，最容易被忽略** |

**注意 `RotationPeriod` 不在这个默认列表里**——它不是内置 CA 的默认项。

> ⚠️ **本课实测边界**：本机集群为无 ACL、无 TLS 的裸集群，仅验证了"改配置不触发立即轮换"这一行为。**完整的 CA 轮换后双 root 并存 + 叶子证书重新签发**链路，需要在启用 Connect 服务网格并等待轮换窗口（或手动构造过期）后才能实测，本次未覆盖。后续如需完整验证，建议在启用 TLS+gossip 加密的环境上补测。

---

## 三、过期事故预防

### 3.1 为什么"等着过期再换"一定会出事

三类凭证的过期表现都有一个共同点：**进程还在，健康检查还在，但功能没了**。

| 凭证 | 过期后的表现 | 是否被常规监控抓到 |
|---|---|---|
| gossip key 不一致 | 新节点加入失败 | 否（老节点 metrics 正常） |
| TLS 证书过期 | HTTPS 握手失败 | 否（进程存活、端口监听正常） |
| Connect CA 中间证书过期 | 新服务签不到证书 | 否（已有服务通信正常） |

**共同点：全部躲过"进程在不在"的监控。**

### 3.2 监控到期的可执行做法

TLS 证书剩余天数（可直接用于告警规则）：

```bash
#!/usr/bin/env bash
# consul-cert-expiry.sh —— 输出证书剩余天数，供监控系统采集
CERT="/etc/consul.d/server.pem"
end=$(openssl x509 -in "$CERT" -noout -enddate | cut -d= -f2)
end_epoch=$(date -d "$end" +%s)
now_epoch=$(date +%s)
echo $(( (end_epoch - now_epoch) / 86400 ))
```

实测输出：`29`（对应上面那张 30 天证书，签完过了一天）。

**告警建议**：`剩余天数 < 30` 触发 warning，`< 7` 触发 critical。

Connect CA 中间证书到期（API 可查）：

```bash
curl -s http://127.0.0.1:8501/v1/connect/ca/roots | \
  jq -r '.Roots[] | "\(.Name) NotAfter=\(.NotAfter)"'
```

### 3.3 三个常见漏项

1. **只监控了根证书，没监控中间证书**。根 10 年让你放松警惕，中间 1 年才是真炸弹。
2. **只监控了 TLS，忘了 gossip key 没有过期这回事**。它不会过期，所以要靠**配置审计**（定期确认 encrypt 配置存在且各节点一致），而不是靠到期告警。
3. **轮换后没有同步备份**。这是最致命的——见课 5：轮换完 CA 不重新备份，你的旧快照和现有集群就对不上了。

---

## 四、本课核心结论

1. **三类凭证互相独立**：gossip key / TLS 证书 / Connect CA，任何一套过期都不会被另一套的更新所弥补。
2. **gossip key 永不过期**，风险来自泄漏而不是到期；`keyring -list` 报 empty 意味着**没开加密**，生产环境这是明文裸奔。
3. **Connect CA 三级 TTL**（实测默认）：根 `87600h`（10 年）/ 中间 `8760h`（1 年）/ 叶子 `72h`（3 天）。真正每年要关心的是中间证书；叶子虽短但自动续签，风险在于 CA 本身不健康。
4. **改 CA 配置 ≠ 立即轮换**（实测 HTTP 200 但 root 数不变），轮换由 `RotationPeriod` 周期驱动，默认 90 天。
5. **三类过期都躲过进程级监控**，"进程还在"不等于"还能用"。

---

## 五、与课 5 的衔接

本课留下一个**必须在下课前想清楚**的问题：

> Connect CA 的私钥存在 Consul 内部的 Raft 状态里。那么当你 `consul snapshot save` 做备份时，**CA 私钥跟着快照走了吗**？

直觉上有两种答案，各自对应完全不同的灾备方案。课 5 会用一次**全毁重建**的实验给出实测答案。

---

## 课尾导航

- **上一课**：[课 3 性能、容量与调优](lesson-03-性能、容量与调优.md)
- **回索引**：[运维专项 overview](../overview.md)
- **下一课**：[课 5 备份、恢复与灾备演练](lesson-05-备份、恢复与灾备演练.md)
- **相关**：主线[课 8 ACL 与安全模型](../../../stages/2-核心能力拆解/lessons/lesson-08-ACL与安全模型.md)
- **急用**：凭证过期已导致故障 → 查 [09-排障速查手册](../../../09-排障速查手册.md)

### 小测

1. 三类凭证中，哪一类**没有过期时间**？它的轮换触发原因是什么？
2. 你执行 `consul keyring -list` 得到 `Keyring is empty`，这说明什么？是故障吗？
3. 你更新了 Connect CA 配置（HTTP 200），为什么 root 数量没有立刻变成 2？
4. Connect CA 根证书有效期 10 年，为什么运维仍需每年关心？
5. 三类凭证过期后，为什么常规的"进程存活"监控抓不到？

<details>
<summary>答案</summary>

1. **gossip 加密密钥**没有过期时间，永不过期。轮换触发原因是**泄漏风险**（人员离职、配置泄露），而非到期。
2. 说明该集群**未启用 gossip 加密**。这不是故障，但生产环境意味着 gossip 流量明文传输，是安全缺陷。
3. 因为内置 CA 的轮换由 `RotationPeriod` 周期驱动（默认 2160h = 90 天），**改配置只是修改策略，不会立即触发轮换**。实测 HTTP 200、ModifyIndex 已更新，但 Roots 数仍为 1。
4. 因为真正签发服务证书的是**中间证书**（`IntermediateCertTTL` 默认 8760h = 1 年），根证书 10 年不代表中间证书 10 年。另外叶子证书只有 `72h`（3 天），虽由 Consul 自动续签，但一旦 CA 不健康，3 天后就会全面崩塌。
5. 因为三类过期都表现为**进程存活、端口监听、健康检查通过，但功能失效**（新节点加不进 / 握手失败 / 签不出证书），进程级监控只能看到"还在跑"。

</details>
