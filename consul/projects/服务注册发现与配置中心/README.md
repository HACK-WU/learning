# 实战项目：服务注册发现与配置中心

> 所属课程：Consul（服务注册/发现与配置选型） ｜ 学习目标：**决策参考** ｜ 预计耗时：3–4 小时
> 实测环境：Windows 11 + Python 3.11 + Consul 2.0.2（dev 模式），2026-08-28 全部代码真跑验证通过

## ⚠️ 先读这一段：本项目的定位

按课程设计，结课综合实战项目应覆盖 **≥3 个阶段**的知识点。但本项目生成时课程只完成 **2/4 阶段**（阶段 1「认识 Consul」+ 阶段 2「核心能力拆解」），阶段 3「横向对比」与阶段 4「决策落地」尚未学习。

因此本项目的准确定位是：**覆盖阶段 1–2 的阶段性实战项目**，它的作用是"把前半程学到的机制焊成一个能跑的东西"，为后续选型判断提供**手感基础**（知道 Consul 的能力边界在哪、坑在哪，才谈得上跟 etcd/Nacos 对比）。

| 复杂度门槛 | 达标情况 |
|---|---|
| ① 跨 ≥3 阶段整合 | ❌ **未达标**——实际覆盖 2 个阶段（课程仅完成 2/4） |
| ② ≥2 项非功能约束 | ✅ 达标——错误处理、可维护性、降级可用性共 3 项 |
| ③ ≥2 个真权衡决策 | ✅ 达标——3 个决策点（见[设计决策.md](./设计决策.md)） |
| ④ 多文件工程 | ✅ 达标——6 个模块的多文件工程，非单文件脚本 |

> 待阶段 3、4 学完后，可在此基础上扩展为达标版结课项目（扩展建议见文末「后续升级方向」）。

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

**跨阶段校验**：覆盖 **2 个阶段**（阶段 1、阶段 2）——门槛要求 ≥3，**未达标**，原因见顶部声明。

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
```

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
| `main.py` | 主演示程序，串起全部六步 |

## 🔧 后续升级方向（待阶段 3、4 学完后）

学完竞品对比与决策落地后，可把本项目升级为达标版结课项目：

1. **加一层对比实现**：用同一套接口抽象，分别用 Consul KV 与 etcd 实现配置中心，实测两者在"配置变更推送延迟""watch 语义差异"上的表现 → 回指阶段 3 课 8/9
2. **加决策产出**：基于本项目实测数据（推送延迟、故障摘除时间、锁交接时间），产出一份"该不该用 Consul 做配置中心"的决策清单 → 回指阶段 4 课 11
3. **加许可证维度**：标注本项目中哪些用法会触发 BUSL 限制 → 回指阶段 4 课 10

## 🧭 导航

- 返回 [课程目录](../../02-课程目录.md)
- 配套排障：[09-排障速查手册.md](../../09-排障速查手册.md)
- 想懂原理：[08-实战经验.md](../../08-实战经验.md)
