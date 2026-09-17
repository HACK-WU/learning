# 实战项目：服务注册发现与配置中心

> 所属课程：Consul（服务注册/发现与配置选型） ｜ 学习目标：**决策参考** ｜ 预计耗时：3–4 小时
> 实测环境：Windows 11 + Python 3.11 + Consul 2.0.2（dev 模式），2026-08-28 全部代码真跑验证通过

## ⚠️ 先读这一段：本项目的定位

按课程设计，结课综合实战项目应覆盖 **≥3 个阶段**的知识点。本项目初版生成时课程只完成 2/4 阶段（阶段 1「认识 Consul」+ 阶段 2「核心能力拆解」），2026-09-17 阶段 3「横向对比」与阶段 4「决策落地」四课正文完成后，项目已就地升级为**覆盖全部 4 个阶段**的达标版结课项目。

升级体现在新增的两步（[stage34_ext.py](./实现/stage34_ext.py)）：**第 7 步**把课 10 的「成品 vs 零件」结论做成可插拔后端抽象，切换后端时缺失能力在第一次调用就抛出；**第 8 步**把课 11「运维五问」与课 12「POC 验收点」做成可执行的 `run_preflight_checks()` 上线前自检。

**2026-09-17 二次升级：吸收三份应用实战篇的实测结论**（第 9、10 步）。

三份实战篇（[A 读模式](../../practices/实战A-读模式实测/README.md) / [B Connect](../../practices/实战B-Connect最小闭环/README.md) / [C ACL](../../practices/实战C-ACL生产权限模型/README.md)）是独立实测，它们产出的结论中，有四条属于"不写进代码就一定会再犯"的硬边界，已全部落地为项目里的约束力：

| 吸收项 | 落到哪里 | 不落地会怎样 |
|--------|---------|-------------|
| 服务发现应用 stale 读 | `discover()` 默认 `consistency='stale'` | leader 选举期间（实测 9.5s）服务发现直接 500 |
| 递归读越权返回 404 而非 403 | `config_center.load_all()` 归因逻辑 | ACL 问题被误判为"空配置"，热更新静默失效 |
| `operator` 等资源不带 label | `validate_acl_rules()` 规则扫描器 | 规则写错时 Consul 不报错，权限静默不生效 |
| Connect 可被绕过 sidecar | 自检项 7 + `demo_service` 监听约束 | 应用监听 `0.0.0.0` 时 mTLS 形同虚设 |

| 复杂度门槛 | 达标情况 |
|---|---|
| ① 跨 ≥3 阶段整合 | ✅ 达标——覆盖 **4 个阶段**（2026-09-17 由 2 阶段升级而来） |
| ② ≥2 项非功能约束 | ✅ 达标——错误处理、可维护性、降级可用性共 3 项 |
| ③ ≥2 个真权衡决策 | ✅ 达标——3 个决策点（见[设计决策.md](./设计决策.md)） |
| ④ 多文件工程 | ✅ 达标——7 个模块的多文件工程，非单文件脚本 |

## 🎯 一句话需求

**做一个"服务自注册 + 客户端发现 + 配置热更新 + 领导者选举"的最小可用中间件**：服务启动后自动注册到 Consul 并维持心跳，消费方按服务名发现健康实例并调用，配置存在 KV 中且变更时秒级推送到所有实例，多实例间能用 Consul 选出一个 leader 干活。

## ✅ 目标与非功能约束

**功能目标**

1. 服务自动注册与注销（含 TTL 心跳维持存活）
2. 消费方按服务名发现健康实例并调用，实例故障后自动收敛
3. KV 配置变更秒级热更新，无需重启服务
4. 基于 session + KV 锁的领导者选举，支持 leader 崩溃后自动交接

**非功能约束（3 项）**

| 约束 | 具体要求 | 落实位置 |
|------|---------|---------|
| **错误处理** | 区分网络层异常与 HTTP 层错误码；404 视作正常业务分支（键不存在）而非异常；所有请求带超时 | [consul_client.py](./实现/consul_client.py) 的 `ConsulError` 与 `_request` |
| **可维护性** | 本地快照 + 原子写（先写 `.tmp` 再 `os.replace`），Consul 不可用时可回落到上次配置启动；配置可导出留档（KV 无版本历史） | [config_center.py](./实现/config_center.py) 的 `_save_snapshot` / `load_snapshot` / `export` |
| **降级可用性** | Consul 完全不可达时，服务仍能凭本地快照启动并提供服务（能力降级但不整体崩溃） | [demo_service.py](./实现/demo_service.py) 的 `try/except` 回落逻辑 |

## 🗺️ 覆盖知识点地图

> 这是"整合"的证据，逐条回指课时。

| 知识点 | 所属阶段 / 课 | 本项目用在何处 | 回指 |
|--------|--------------|---------------|------|
| 服务寻址难题（硬编码 IP → 注册中心） | 阶段 1 · 课 1 | 消费方不再硬编码 `127.0.0.1:18081`，改为按 `demo-svc` 名字发现 | [lesson-01](../../stages/1-认识Consul/lessons/lesson-01-为什么需要服务注册与发现.md) |
| 客户端发现模式 | 阶段 1 · 课 1 | `service_registry.discover_and_call`：消费方自己拿列表、自己选实例直连，Consul 不转发 | [lesson-01](../../stages/1-认识Consul/lessons/lesson-01-为什么需要服务注册与发现.md) |
| 架构角色（Server/Client/DC） | 阶段 1 · 课 2 | 应用只与本机 Client agent（`:8500`）通信，代码里不出现任何 Server 地址 | [lesson-02](../../stages/1-认识Consul/lessons/lesson-02-Consul是什么与能力全景.md) |
| 服务注册与健康检查 | 阶段 1 · 课 3 / 阶段 2 · 课 4 | `ServiceRegistry.register` 带 TTL 检查 + DCSA；心跳线程按 TTL/2 上报 | [lesson-03](../../stages/1-认识Consul/lessons/lesson-03-五分钟跑起来看一眼.md)、[lesson-04](../../stages/2-核心能力拆解/lessons/lesson-04-服务发现与健康检查机制.md) |
| 健康检查的两种模型（push/pull） | 阶段 2 · 课 4 | TTL 是 push（应用上报），HTTP/TCP 是 pull（agent 探测）——本项目用 TTL 并说明取舍 | [lesson-04](../../stages/2-核心能力拆解/lessons/lesson-04-服务发现与健康检查机制.md) |
| catalog 视图 vs health 视图 | 阶段 2 · 课 4 | `discover()` 刻意用 `/v1/health/service`（带健康过滤）而非 `/v1/catalog/service` | [lesson-04](../../stages/2-核心能力拆解/lessons/lesson-04-服务发现与健康检查机制.md) |
| Raft 与 leader | 阶段 2 · 课 5 | `main.py` 第 6 步观测 `leader` / `peers`，并说明无 leader 时写入会失败 | [lesson-05](../../stages/2-核心能力拆解/lessons/lesson-05-Raft与Gossip一致性成色.md) |
| KV 存储与前缀查询 | 阶段 2 · 课 6 | 配置按 `demo/` 前缀组织，`recurse=true` 一次拉全量 | [lesson-06](../../stages/2-核心能力拆解/lessons/lesson-06-KV存储与配置管理.md) |
| 阻塞查询（长轮询） | 阶段 2 · 课 6 | `ConfigCenter.wait_update` 用 `X-Consul-Index` + `wait` 实现秒级热更新 | [lesson-06](../../stages/2-核心能力拆解/lessons/lesson-06-KV存储与配置管理.md) |
| 会话（session）与分布式锁 | 阶段 2 · 课 6 | `lock.py` 用 session + KV acquire 做领导者选举 | [lesson-06](../../stages/2-核心能力拆解/lessons/lesson-06-KV存储与配置管理.md) |
| KV 当配置中心的局限 | 阶段 2 · 课 6 | 无版本历史 → `export()` 外部留档；无审计 → 落盘快照留痕 | [lesson-06](../../stages/2-核心能力拆解/lessons/lesson-06-KV存储与配置管理.md) |
| 成品 vs 零件的赛道分层 | 阶段 3 · 课 10 | `DiscoveryBackend` 抽象只暴露服务发现语义；etcd/ZK 作为零件型后端缺失健康检查等能力时抛 `CapabilityGap` | [lesson-10](../../stages/3-横向对比/lessons/lesson-10-多维对比矩阵.md) |
| 能力矩阵的可执行化 | 阶段 3 · 课 9/10 | `CAPABILITIES` 表把「谁有什么」写成数据，`compare()` 直接打印对比矩阵，避免口头选型 | [lesson-09](../../stages/3-横向对比/lessons/lesson-09-四大竞品逐个看.md)、[lesson-10](../../stages/3-横向对比/lessons/lesson-10-多维对比矩阵.md) |
| 许可证风险（BUSL 1.1） | 阶段 4 · 课 11 | 能力对比表输出各后端许可证；自检项提示生产使用前须过一遍许可证自查 | [lesson-11](../../stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md) |
| 上线前自检 / POC 验收点 | 阶段 4 · 课 11/12 | `run_preflight_checks()` 八项检查：leader、quorum、KV 可用性、ACL 默认拒绝、指标三步核验、快照演练、网格绕过、ACL 规则语法 | [lesson-11](../../stages/4-决策落地/lessons/lesson-11-许可证成本与风险.md)、[lesson-12](../../stages/4-决策落地/lessons/lesson-12-选型决策框架与场景结论.md) |
| 服务发现用 stale 读 | 实战篇 A（三节点实测） | `discover()` 默认 `consistency='stale'`，换取 leader 选举期间的可用性 | [实战篇 A](../../practices/实战A-读模式实测/README.md) |
| 递归读越权的 404 伪装 | 实战篇 C（21 项矩阵实测） | `load_all()` 遇 404 用裸路径单键读复核，403 即抛 `PermissionError` | [实战篇 C](../../practices/实战C-ACL生产权限模型/README.md) |
| ACL 规则 label 写法 | 实战篇 C（实测 + 官方核实） | `validate_acl_rules()` 扫描 `operator`/`acl` 等被误写成 `_prefix` 的情况 | [实战篇 C](../../practices/实战C-ACL生产权限模型/README.md) |
| Connect 可被绕过 sidecar | 实战篇 B（mTLS 实测） | 自检项 7 + `demo_service.py` 只监听 `127.0.0.1` | [实战篇 B](../../practices/实战B-Connect最小闭环/README.md) |

**跨阶段校验**：覆盖 **4 个阶段**（阶段 1、2、3、4）——门槛要求 ≥3，**已达标**（2026-09-17 升级）。

**自检结果如实说明**：本项目跑在 dev 单节点上，第 8 步会报「通过 2 / 警告 2 / 不通过 1 / 跳过 1」。其中 quorum 不通过是**正确判定**（单节点本就不满足生产 quorum），ACL 跳过是**能力边界**（dev 模式无法区分"未启用"与"已启用但放行"，代码如实标 skip 而不是猜一个结论）。这两项不是缺陷，是自检项在诚实报环境状态。

## 🚀 运行方式

**前置**：本机已启动 Consul（`consul agent -dev`），且 Python 3.9+（仅用标准库，无需 pip 安装任何依赖）。

```powershell
# 1) 启动 Consul（另开一个终端）
consul agent -dev

# 2) 跑主演示：注册 2 个实例 → 发现调用 → 故障摘除 → 配置热更新 → 领导者选举 → 集群观测
cd 实现
python main.py

# 3) 跑真实服务端到端（另开终端）：服务真监听端口，改 KV 后不重启即生效
python demo_service.py
#   然后访问 http://127.0.0.1:18081/ 看响应里的 greeting 字段
```

**预期结果**（本机实测输出，2026-08-28）：

```text
第 1 步：注册两个服务实例 → 发现结果：['demo-svc-1', 'demo-svc-2']
第 3 步：注销 demo-svc-2 → 剩余健康实例：['demo-svc-1']（自动收敛）
第 4 步：阻塞查询在 1023ms 内检测到变更 → 新配置：{..., 'feature_flag': 'on-133126'}
第 5 步：worker-1 抢占 True / worker-2 抢占 False / 释放后 worker-2 抢占 True
第 6 步：当前 leader：127.0.0.1:8300
第 7 步：打印三后端能力矩阵；切到 etcd 时「健康检查/DNS/服务网格」三项首次调用即抛 CapabilityGap
第 8 步：通过 2 项 / 警告 4 项 / 不通过 1 项 / 跳过 1 项（quorum FAIL 是 dev 单节点的正确判定）
第 9 步：四种场景的读模式推荐；stale 模式发现 1 个健康实例
第 10 步：扫描出 2 处 ACL 规则写法错误（operator / acl 用了 _prefix 形式）
```

> 第 7–10 步为 2026-09-17 两次升级新增，实测环境同上（Consul 2.0.2 dev 模式）。
> 第 9 步的 LastContact 在 dev 单节点下恒为 0（无落后可测），
> 三节点实测值见 [实战篇 A](../../practices/实战A-读模式实测/README.md)（stale 为 15~45ms）。

真实服务端到端实测（改 KV 不重启服务）：

```text
改前：{"service":"demo-svc-1","greeting":"Hot-reloaded value!","feature_flag":"on",...}
改后：{"service":"demo-svc-1","greeting":"Hot-reloaded OK!","feature_flag":"on",...}
服务日志：[配置] 检测到变更并热更新：{'feature_flag': 'on', 'greeting': 'Hot-reloaded OK!'}
```

## 📁 目录说明

| 路径 | 内容 |
|------|------|
| [设计决策.md](./设计决策.md) | 3 个权衡点的完整论证（TTL vs HTTP 检查、阻塞查询 vs 轮询、Consul 锁 vs 外部选主） |
| [反例对照.md](./反例对照.md) | "能跑但很糟"的版本 + 逐条对比（4 条差异） |
| [实现/](./实现/) | 可运行代码（中文注释，关键处注明对应知识点） |
| [验收清单.md](./验收清单.md) | 自测项，逐项勾选 |

`实现/` 内文件：

| 文件 | 职责 |
|------|------|
| `consul_client.py` | Consul HTTP 客户端封装（注册/发现/KV/会话/集群观测），错误处理与超时控制 |
| `service_registry.py` | 服务注册 + TTL 心跳生命周期 + 健康实例发现 + 客户端发现调用 |
| `config_center.py` | KV 配置加载、阻塞查询热更新、本地快照降级、导出留档 |
| `lock.py` | 基于 session + KV 锁的分布式锁与领导者选举 |
| `demo_service.py` | 演示用业务服务（真实监听端口，展示配置热更新） |
| `stage34_ext.py` | 阶段 3/4 扩展：可插拔注册后端抽象（`DiscoveryBackend` + 能力矩阵 `CAPABILITIES`）+ 上线前运维自检 `run_preflight_checks()` |
| `main.py` | 主演示程序，串起全部八步（阶段 1–4） |

## 🔧 升级记录与后续方向

**2026-09-17 已完成升级**（阶段 3/4 正文完成后就地扩展，见 [stage34_ext.py](./实现/stage34_ext.py)）：

1. **对比实现**：`DiscoveryBackend` 抽象 + `CAPABILITIES` 能力表，切换后端时缺失能力在第一次调用抛 `CapabilityGap` → 回指阶段 3 课 9/10
2. **决策产出**：`run_preflight_checks()` 把课 11「运维五问」与课 12「POC 验收点」做成八项可执行自检 → 回指阶段 4 课 11/12

**2026-09-17 二次升级：吸收三份实战篇**（第 9、10 步，见上表）：

3. **读模式落地**：`discover()` 默认改 stale；`consul_client` 透出 `X-Consul-LastContact`；`pick_read_mode()` 按场景推荐
4. **权限归因**：`load_all()` 区分"空配置"与"无权限"——递归读 404 后用裸路径单键读复核
5. **规则校验**：`validate_acl_rules()` 扫描 `operator`/`acl` 等不带 label 资源被误写成 `_prefix` 的情况
6. **网格边界**：自检新增"网格不可被绕过"项，并在 `demo_service.py` 落实只监听 `127.0.0.1`

**顺带修复的两个既有缺陷（发现于吸收过程）**：

- `config_center.load_all()` 未处理空前缀 404 → **首次运行即崩溃**。已加 try/except，并补权限归因
- `main.py` 第 4 步 `waiter` 只调 `wait_update` **一次** → 空前缀时阻塞查询 2ms 立即返回，等待机会用完，**首次运行的第一分钟热更新完全失效**。已改为循环重试（2026-09-17 实测修复后约 1000ms 检测到变更）

> 修复过程中曾尝试用 `_fetch_current_index()` 取空前缀起始 index，**实测证明无效**（空前缀查询本身返回 404，且 404 响应头未保留），已按诚实纪律撤回，未留假装修好的代码，限制如实记录在 `load_all()` 的 404 分支注释里。

**仍可继续深挖的方向**（非门槛要求，有余力再做）：

3. **真跑第二个后端**：目前 etcd 分支只到"能力拦截"为止（未安装 etcd），若要实测 watch 语义差异需装 etcd 并对比推送延迟 → 回指阶段 3 课 9
4. **mTLS 数据面**：把课 7 的 Connect 接进本项目的服务调用（需 Envoy，本机未装），使"服务网格"能力从静态声明变为可演示 → 回指阶段 2 课 7

## 🧭 导航

- 返回 [课程目录](../../02-课程目录.md)
- 配套排障：[09-排障速查手册.md](../../09-排障速查手册.md)
- 想懂原理：[08-实战经验.md](../../08-实战经验.md)
