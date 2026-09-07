# 实战项目：从告警到定位——一条龙可观测性平台

> 所属课程：Grafana 系统学习（12 课 / 36 知识点全结课）
> 项目类型：技术域 · 可运行工程 ｜ 难度：结课级（跨 4 阶段整合）

## 一句话需求

**当告警在半夜响起时，值班的人能在 3 分钟内从「收到告警」走到「定位到根因」，中间不需要开第二个控制台、不需要手工换算时间戳。**

## 为什么是这个项目

回想课程开课时定的故事主线：

- **主角**：一张 dashboard
- **冲突**：指标、日志、链路散在三个系统，出事要开三个控制台、手工对齐时间戳
- **收束**：同一时间窗口内指标 → 日志 → 链路三级下钻

前 12 课分别解决了"能看见""查得到""叫得醒""管得住"，但没有哪一课把它们串起来。**这个项目就是那个"合"**——把散装的知识点焊成"出事了能处理"的能力。

## 目标（验收标准）

| # | 目标 | 怎么算达成 |
|---|------|-----------|
| 1 | 告警能真的响 | 注入故障后 webhook 收到真实告警（不是界面上"看到规则存在"） |
| 2 | 指标能定位到慢接口 | P90 延迟图上能看出是哪个 route 慢 |
| 3 | 指标能跳链路 | 图上出现 exemplar 圆点，点开是对应 trace |
| 4 | 日志能按 trace_id 检索 | 用 trace_id 能在 Loki 精准捞到那次请求的所有日志 |
| 5 | 链路能看到耗时分布 | Jaeger 里能看到根 span 与子 span 各自的耗时 |
| 6 | 全部配置可重建 | 删掉 Grafana 容器，一条命令恢复全部配置 |

## 覆盖知识点地图

**覆盖 4 个阶段 / 10 个知识点**（门槛要求 ≥3 阶段）。

| 知识点 | 阶段 / 课 | 在本项目中的落点 |
|---|---|---|
| 数据源插件模型 | 阶段 1 · 课 1 | 三个数据源（Prom / Loki / Jaeger）通过插件协议共存 |
| 第一个 Panel | 阶段 1 · 课 2 | RED 三件套面板（QPS / 错误率 / P90） |
| 变量入门 | 阶段 1 · 课 3 | `$route` 变量驱动全盘查询 |
| Row 与 JSON Model | 阶段 1 · 课 3 | 9 个面板的 dashboard JSON，脚本生成可版本化 |
| 查询编辑器三态 | 阶段 2 · 课 4 | 全部用 Code 模式写 PromQL，不点 Builder |
| 一次查询的完整旅程 | 阶段 2 · 课 4 | Grafana → 后端代理 → Prometheus 的链路 |
| Transformations | 阶段 2 · 课 5 | 日志面板用 `\| json` 解析结构化字段 |
| 变量进阶（多值/All） | 阶段 2 · 课 6 | `$route` 支持多选与 All，`=~` 正则匹配 |
| 统一告警架构 | 阶段 3 · 课 7 | 3 条告警规则 + 状态机 + No Data 处理 |
| 通知策略树与静默 | 阶段 3 · 课 8 | 按 severity/signal 分级路由 + 分组 + 维护窗口 |
| 指标到日志下钻 | 阶段 3 · 课 9 | 日志的 `derivedFields` 让 trace_id 可点击 |
| 链路与 exemplar | 阶段 3 · 课 9 | exemplar 把 trace_id 挂到 histogram 观测上 |
| Provisioning 三类文件 | 阶段 4 · 课 10 | 数据源 / dashboard / 告警全部 YAML 化 |
| 服务账号与 API Key | 阶段 4 · 课 11 | 验收脚本用 API 调用（Bearer token） |
| 性能瓶颈 | 阶段 4 · 课 12 | 数据源配 `maxDataPoints: 1000` 控制响应体 |

> 阶段 1（3 个）+ 阶段 2（4 个）+ 阶段 3（4 个）+ 阶段 4（4 个）= **15 个知识点，覆盖全部 4 个阶段**。

## 运行方式

### 前置条件

- Windows + WSL2 + Docker Desktop（本项目实测环境：WSL Ubuntu / Docker / Grafana 13.2.1）
- 已有容器网络 `grafana-net`（项目复用它，避免重复造轮子）
- 磁盘 ≥ 2GB

### 一键启动

```bash
bash /mnt/d/projects/learning/grafana/projects/从告警到定位/实现/up.sh
```

### 一键停止

```bash
bash /mnt/d/projects/learning/grafana/projects/从告警到定位/实现/down.sh
```

### 手动分步（理解每一步在做什么）

```bash
W=/mnt/d/projects/learning/grafana/projects/从告警到定位
```

```bash
docker build -t p3-shop:1.1 "$W/实现/app"
```

```bash
docker run -d --name p3-shop --network grafana-net -p 9400:9400 -p 9401:9401 -e OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces -e LOKI_URL=http://grafana-loki:3100/loki/api/v1/push -e FAULT_MODE=0 -v "$W/实现/app/logs:/var/log/shop" p3-shop:1.1
```

```bash
docker run -d --name p3-prom --network grafana-net -p 3110:9090 -v "$W/实现/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" prom/prometheus:v3.14.0 --config.file=/etc/prometheus/prometheus.yml --enable-feature=exemplar-storage
```

```bash
docker run -d --name p3-webhook --network grafana-net -p 9402:8080 -v "$W/实现/webhook/webhook.py:/app/webhook.py:ro" -v "$W/实现/webhook/out:/out" python:3.12-slim python -u /app/webhook.py
```

```bash
docker run -d --name p3-grafana --network grafana-net -p 3130:3000 -e GF_SECURITY_ADMIN_PASSWORD=admin -v "$W/实现/provisioning:/etc/grafana/provisioning:ro" -v "$W/dashboards:/var/lib/grafana/dashboards:ro" grafana/grafana:13.2.1
```

### 访问入口

| 服务 | 地址 | 说明 |
|---|---|---|
| **Grafana** | http://localhost:3130 | 主战场，admin / admin |
| 主 Dashboard | http://localhost:3130/d/shop-overview | 9 面板总览盘 |
| Prometheus | http://localhost:3110 | 指标查询 |
| 应用指标 | http://localhost:9400/metrics | 原始指标 |
| 告警 webhook | http://localhost:9402 | 收到的告警落盘到 `实现/webhook/out/` |

## 目录说明

```
从告警到定位/
├── README.md              ← 本文件：需求 / 知识点地图 / 运行方式
├── 设计决策.md            ← 3 个真权衡点（含放弃的方案与代价）
├── 反例对照.md            ← "能跑但很糟"的版本 + 逐条对比
├── 验收清单.md            ← 自测项，逐项勾选
├── dashboards/
│   └── shop-overview.json ← 主 dashboard（脚本生成，可版本化）
└── 实现/
    ├── up.sh / down.sh    ← 一键启停
    ├── gen_dashboard.py   ← dashboard 生成器
    ├── probe_tpl.py       ← 告警模板验证探针（排查用）
    ├── app/
    │   ├── mock_shop.py   ← 被监控应用（指标+日志+链路三件套）
    │   ├── loki_push.py   ← 日志直推 Loki（含为何绕开 Promtail）
    │   ├── Dockerfile
    │   └── logs/          ← 日志落盘（gitignore）
    ├── prometheus/
    │   └── prometheus.yml ← 抓取配置（含 exemplar-storage）
    ├── promtail/
    │   └── promtail.yml   ← 【保留但未启用】生产应选它，WSL 下不可用
    ├── provisioning/
    │   ├── datasources/ds.yaml        ← 3 个数据源 + exemplar + derivedFields
    │   ├── dashboards/dash.yaml       ← dashboard provider
    │   └── alerting/
    │       ├── alert-rules.yaml       ← 3 条告警规则
    │       └── notify.yaml            ← 通知策略树 + 联系人 + 静默
    └── webhook/
        ├── webhook.py     ← 告警接收器（验证告警真的发出去了）
        └── out/           ← 收到的告警 JSON（gitignore）
```

## 关键设计（一句话版）

| 环节 | 怎么实现的 | 为什么 |
|---|---|---|
| 指标 → 链路 | histogram 显式传 `exemplar={'trace_id': ...}` | prometheus_client **不会自动挂**，不传图上没有圆点 |
| 日志 → 链路 | 日志写 `trace_id` + 数据源配 `derivedFields` | 让日志里的 trace_id 变成可点击链接 |
| 链路 → 日志 | 数据源配 `tracesToLogs` | 反向也能跳回去 |
| 告警分级 | 策略树按 `severity` / `signal` 路由 | critical 走 10s 快通道，warning 走 30s 攒批次 |
| 全配置可重建 | provisioning YAML + dashboard JSON | 删掉容器，重启即恢复 |

## 下一步

- 做完照着 [验收清单.md](验收清单.md) 逐项打勾
- 想理解"为什么这么选" → [设计决策.md](设计决策.md)
- 想知道"哪些写法是坑" → [反例对照.md](反例对照.md)
