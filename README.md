# Learning · 个人技术学习仓库

> 以「课程制」方式系统学习技术主题：每门课程自带学习档案、路径总览与课件体系，支持断点续学。

[![courses](https://img.shields.io/badge/courses-9-blue)](#课程导航)
[![Celery + Django](https://img.shields.io/badge/Celery%2B_Django-10%2F10-yellowgreen)](celery-django/02-课程目录.md)
[![Consul](https://img.shields.io/badge/Consul-7%2F11-yellow)](consul/02-课程目录.md)
[![Design Patterns](https://img.shields.io/badge/Design_Patterns-12%2F12-yellowgreen)](design-patterns/02-课程目录.md)
[![Elasticsearch](https://img.shields.io/badge/Elasticsearch-7%2F14-yellow)](elasticsearch/02-课程目录.md)
[![InfluxDB](https://img.shields.io/badge/InfluxDB-4%2F19-yellow)](influxdb/02-课程目录.md)
[![Kafka](https://img.shields.io/badge/Kafka-10%2F10-yellowgreen)](kafka/02-课程目录.md)
[![PromQL](https://img.shields.io/badge/PromQL-12%2F12-yellowgreen)](promql/02-课程目录.md)
[![RabbitMQ](https://img.shields.io/badge/RabbitMQ-4%2F12-yellow)](rabbitmq/02-课程目录.md)
[![ZooKeeper](https://img.shields.io/badge/ZooKeeper-15%2F15-brightgreen)](zookeeper/02-课程目录.md)

## 概述

本仓库收录九门系统化技术课程，覆盖后端常用领域：Celery + Django 异步任务、Consul 服务注册发现、设计模式（Python 实现）、Elasticsearch 搜索、InfluxDB 时序数据库、Kafka 消息队列、PromQL 监控查询语言、RabbitMQ 消息中间件、ZooKeeper 分布式协调。

相比零散笔记，课程制结构解决两个问题：

- **碎片化学习难以成体系**：课程按「阶段 → 课 → 知识点」三级拆分，配故事主线与递进式设计，把完整主题讲透
- **中断后难以续学**：每门课程的 `00-学习档案.md` 记录学习者画像、知识点级进度与评审记录，是断点续学的唯一依据

## 课程导航

| 课程 | 主题 | 基础要求 | 进度 | 状态 |
|------|------|----------|------|------|
| [Celery + Django](celery-django/02-课程目录.md) | Celery 异步任务体系与 Django 集成，从异步化动因、可靠性幂等到并发模型、编排与生产运维 | Django 熟，Celery 入门 | 10 / 10 课 | 🔶 收尾中 |
| [Consul](consul/02-课程目录.md) | 服务注册发现与配置中心，从能力拆解到横向对比与选型决策（决策参考导向） | 入门 | 7 / 11 课 | 🔄 进行中 |
| [设计模式](design-patterns/02-课程目录.md) | GoF 设计模式的 Python 惯用实现，以订单系统重构为故事主线 | Python 基础扎实 | 12 / 12 课 | 🔶 收尾中 |
| [Elasticsearch](elasticsearch/02-课程目录.md) | 从「数据库为什么搞不定搜索」到查询聚合、分布式与选型，附认证备考映射 | 零基础 | 7 / 14 课 | 🔄 进行中 |
| [InfluxDB](influxdb/02-课程目录.md) | InfluxDB 3 时序数据库，从「为什么不用 MySQL」到生产落地与选型决策 | 零基础 | 4 / 19 课 | 🔄 进行中 |
| [Kafka 基础](kafka/02-课程目录.md) | 从消息队列概念到集群可靠性与事件驱动架构，Docker 实操贯穿全程 | 零基础 | 10 / 10 课 | 🔶 收尾中 |
| [PromQL](promql/02-课程目录.md) | Prometheus 查询语言，从数据模型到告警规则与 Grafana 面板，含 SLO 实战项目 | 零基础 | 12 / 12 课 | 🔶 收尾中 |
| [RabbitMQ 基础](rabbitmq/02-课程目录.md) | 从「为什么需要消息队列」到生产落地，Python（pika）实操贯穿全程，止于选型决策 | 零基础 | 4 / 12 课 | 🔄 进行中 |
| [ZooKeeper](zookeeper/02-课程目录.md) | 分布式协调服务，从零基础上手到核心机制、选型决策，含结课实战项目与排障手册 | 零基础→入门 | 15 / 15 课 | ✅ 已完成 |

> 进度为 2026-08-31 快照，实时状态以各课程 `00-学习档案.md` 为准。
>
> 状态图例：✅ 已完成 = 全部课时与收尾环节（结课项目 / 课程手册 / 排障手册）均交付；🔶 收尾中 = 全部课时讲完，收尾环节待生成；🔄 进行中 = 尚有课时未编写。

每门课程的三个入口：

- `00-学习档案.md` — 断点续学唯一依据：学习者画像、知识点级进度、评审与事实核查记录
- `01-学习路径总览.md` — 全局路径图：阶段划分、依赖关系与学习顺序
- `02-课程目录.md` — 全部课件索引：按阶段组织，直达每一课

## 仓库结构

```text
learning/
├── README.md                 # 本文件：仓库总导航
├── celery-django/            # Celery + Django 课程（4 阶段 10 课）
│   ├── 00-学习档案.md / 00-评审清单.md
│   ├── 01-学习路径总览.md / 02-课程目录.md
│   ├── assets/               # 课程级 SVG 图表
│   ├── playground/           # 实测脚本（l9/l10 基准与验证）
│   └── stages/               # 4 个阶段目录：overview.md + lessons/lesson-XX.md
├── consul/                   # Consul 课程（4 阶段 11 课，含 payloads/ 与 projects/）
├── design-patterns/          # 设计模式课程（4 阶段 12 课，Python）
├── elasticsearch/            # Elasticsearch 课程（5 阶段 14 课，含 playground/ 实测脚本）
├── influxdb/                 # InfluxDB 3 课程（6 阶段 19 课）
├── kafka/                    # Kafka 基础课程（4 阶段 10 课，含 final-课程手册.md）
├── promql/                   # PromQL 课程（4 阶段 12 课，含 projects/ 可观测性体系）
├── rabbitmq/                 # RabbitMQ 课程（4 阶段 12 课，含 playground/ 实测脚本）
└── zookeeper/                # ZooKeeper 课程（5 阶段 15 课，含结课项目与排障手册）
```

各课程内部体例一致：`00-学习档案.md`（进度与评审）、`00-评审清单.md`（待办勾选）、`01-学习路径总览.md`、`02-课程目录.md`、`assets/`（SVG）、`stages/`（阶段与课件）。部分课程另有扩展目录：`playground/`（本机实测脚本）、`projects/`（结课实战项目）、`08-实战经验.md` 与 `09-排障速查手册.md`（收尾产物）。

阶段目录命名形如 `stages/1-地基与创建型/`，每个阶段包含一份 `overview.md`（阶段导览）与 `lessons/` 目录（课件正文）；尚未开讲的阶段随学习进度逐步落盘课件（如 `elasticsearch/` 阶段 4-5、`influxdb/` 阶段 3-6 目前只有阶段导览）。

## 如何学习

**首次进入某门课程**：

1. 读该课程的 `01-学习路径总览.md`，了解阶段划分与整体脉络
2. 打开 `02-课程目录.md`，从第一课或进度标记的当前课开始
3. 按顺序逐课推进，每课末尾附课程导航（上一课 / 下一课链接）

**断点续学**：

1. 先读该课程的 `00-学习档案.md`，定位进度表中第一个未完成项
2. 九门课程均含 `00-评审清单.md`：先读它，存在未勾选条目时先补对应评审，再继续下一批
3. 从未完成课继续，完成后将进度回写档案

**课件体例与质量约定**：

- 课件以 Markdown 为主载体，简单结构图用 Mermaid、复杂机制图与路径图用 SVG（存放于各课程 `assets/` 目录）
- 代码示例均为可运行代码；关键事实（版本号、历史时间线等）经联网核实后记录在档案中
- 课件按批次交付，每批次经教学法 + 学习者双视角评审，问题修复清零后归档，评审记录见各档案
- 收尾环节为课程制必做项：结课综合实战项目（Phase 3）、课程手册汇总（Phase 4）、实战经验与排障速查手册（Phase 5），完成后课程才算真正结课
