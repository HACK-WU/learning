# Phase 3 综合实战：电商实时数仓

> **一句话**：把 12 课、36 个知识点塞进一条能真跑的链路里 —— 从 MySQL 的"报表 3 分钟"困境出发，在本机 Doris 上建一套 ODS → DWD → DWS → ADS 四层数仓，接入批量与实时两条链路，做加速调优，推到生产可用，最后验收并划清边界。

---

## 📋 任务清单

| # | 任务 | 锚定课程 | 状态 |
|---|------|---------|------|
| 1 | [需求与建模](./task-1-需求与建模.md) | 课 1、课 3、课 4、课 12 | ✅ 已完成（五表 + 28 分区 + 维表 8 省全覆盖） |
| 2 | [数据接入：批量 + 实时双链路](./task-2-数据接入.md) | 课 6、课 4 | ✅ 已完成（12/12 月对账 PASS、collision_loss=0） |
| 3 | [查询加速与调优](./task-3-查询加速与调优.md) | 课 5、课 7、课 8 | ✅ 已完成（Rollup/MV/Colocate/Profile 全跑通） |
| 4 | [生产化：副本、隔离、变更、备份](./task-4-生产化.md) | 课 9、课 10、课 11 | ✅ 已完成（资源组 + 备份恢复对账一致） |
| 5 | [验收与边界](./task-5-验收与边界.md) | 全课程 + 课 12 | ✅ 已完成（四层对账 + 五个反模式实测） |

**依赖关系**：Task 1 → Task 2 → Task 3 → Task 4 → Task 5。必须按顺序做，前一任务产出的数据是后一任务的输入。

---

## 🏗️ 整体架构

```text
                         ┌──────────────────────────────────────┐
   历史数据（批量）        │        电商实时数仓（dw 库）            │
                         │                                      │
  shop.orders ──导出──┐   │  ┌────────┐   ┌────────┐            │
  (2150万行/脏数据)    │   │  │  ODS   │──▶│  DWD   │            │
                     ▼   │  │ 贴源层  │   │ 去重层  │            │
              ┌──────────┤  └────────┘   └───┬────┘            │
              │  MinIO   │                   │                  │
              │  (S3)    │                   ▼                  │
              └────┬─────┤              ┌────────┐              │
                   │     │              │  DWS   │              │
       S3 TVF /    │     │              │ 汇总层  │              │
       Broker Load │     │              └───┬────┘              │
                   ▼     │                  ▼                   │
              ┌──────────┤              ┌────────┐   ┌────────┐ │
              │          │              │  ADS   │◀──│ 异步MV  │ │
              │          │              │ 应用层  │   └────────┘ │
   实时数据（增量）       │              └────────┘              │
                         │                                      │
  Kafka ──Routine Load──▶│  ODS（实时分区）                        │
  (doris_orders)         │                                      │
                         └──────────────────────────────────────┘
```

**四层职责**

| 层 | 全称 | 表模型 | 职责 | 锚定 |
|----|------|--------|------|------|
| ODS | Operational Data Store | Duplicate | 贴源，原样落地，不做清洗 | 课 3 |
| DWD | Data Warehouse Detail | Unique (MoW) | 去重 + 清洗，明细粒度 | 课 3、课 4 |
| DWS | Data Warehouse Summary | Aggregate | 按维度预聚合 | 课 3、课 5 |
| ADS | Application Data Store | Duplicate / Aggregate | 面向报表的最终结果 + 物化视图 | 课 5、课 8 |

---

## 🧪 实验边界表（先读这一节）

> 本机是**单机伪多节点**环境，很多生产特性跑不出来。下表明确标注每个能力的可验证程度，凡是没跑过的，**一个数字都不会编**。

| 能力 | 状态 | 本机实际情况 |
|------|------|-------------|
| Doris 集群（1 FE + 2 BE） | 🟢 已实测 | 容器 `doris-learn`，4.1.3-rc02，healthy |
| 三种表模型（Dup/Uniq/Agg） | 🟢 已实测 | 课 3 已验证，本项目复用 |
| 分区裁剪 / 分桶 | 🟢 已实测 | 课 4 已验证 |
| parquet 导出 + S3 TVF 回读 | 🟢 已实测 | 指纹一致（见 Task 2） |
| Routine Load（Kafka 实时） | 🟢 已实测 | 消费正常（见 Task 2） |
| Rollup / 异步物化视图 | 🟢 已实测 | 见 Task 3 |
| Colocate Join | 🟢 已实测 | `shop.prov_group` 组 IsStable=true |
| 多副本（replication_num=2） | 🟢 已实测 | 本机 2 BE 允许建 2 副本 |
| S3 备份 / 恢复 | 🟢 已实测 | 见 Task 4 |
| Schema Change（加列/改列） | 🟢 已实测 | `light_schema_change` 默认 true，毫秒级 |
| 动态分区 | 🟢 已实测 | 见 Task 1 |
| Profile 定位慢查询 | 🟢 已实测 | 见 Task 3 |
| **Workload Group CPU 配额** | 🟡 部分实测 | **cgroup 只读挂载，CPU 限额完全不生效**（课 10 实测），只能验证并发/排队/内存 |
| **多副本抗宕机** | 🔴 未实测 | 2 台 BE 的 host 都是 127.0.0.1，反亲和规则不允许同主机多副本扛宕机 |
| **存算分离 / cloud mode** | 🔴 未实测 | 本机存算一体（`RemoteUsedCapacity=0.000`），`SHOW COMPUTE GROUPS` 报 cloud mode only |
| **ClickHouse / ES / Hive 对比** | 🔴 未实测 | 本机无这些容器，不做跑分 PK |

---

## 🎯 验收标准

全部任务做完后，这套数仓应能同时满足：

1. **数据完整性**：ODS 落库指纹 = 源表指纹；DWD 去重后行数可解释（2150 万 → 2000 万）
2. **实时性**：Kafka 新消息在 30 秒内可在 DWD 查到
3. **性能**：5 个核心报表查询全部亚秒级（见 Task 5 逐条实测）
4. **生产化**：有副本、有资源隔离、有备份、有变更流程（见 Task 4）
5. **边界清晰**：能说出哪些需求**不该**接进 Doris（见 Task 5）

### 🟢 五条标准的实测结果

| # | 标准 | 实测结果 | 判定 |
|---|------|---------|------|
| 1 | 数据完整性 | 12 个月逐月对账全 PASS（行数差 0 / 金额差 0.00）、`collision_loss=0` | ✅ |
| 2 | 实时性 | Kafka 消息 **19 秒**可见（< 30 秒） | ✅ |
| 3 | 性能 | 5 个核心查询 **0.102 - 0.162 s**，全部亚秒级 | ✅ |
| 4 | 生产化 | 资源组 2 个、备份快照 OK、分区 28 个正常滚动 | ✅ |
| 5 | 边界清晰 | 五个反模式全部实测（含 order_id 非全局唯一） | ✅ |

> ⚠️ **两处口径说明，别误读**：
>
> 1. **ODS 只有源表一半数据（1100 万 vs 2150 万）是设计如此** ——
>    源表覆盖 24 个月，本项目只导了 2025 全年 12 个月，
>    2026 年是"未来数据"，留给实时链路。逐月对账 12/12 全 PASS。
> 2. **副本数全部是 1，不是生产的 3** —— 本机 2 台 BE 的 host 都是
>    `127.0.0.1`，反亲和规则不允许 3 副本。生产部署时必须改成 3。
>
> 🔴 **另有一条标准本机测不出来，如实标注**：**分区裁剪的性能收益**。
> 带函数与不带函数耗时持平（0.123-0.162 vs 0.124-0.162），
> 因为 0.12 秒的固定开销淹没了裁剪收益。裁剪**是否发生**已在
> Task 3 用 EXPLAIN 的 `partitions=1/28` 验证，但**收益**未实测。

---

## ⚠️ 全课程踩坑清单（本项目会全部遇到）

| # | 坑 | 出处 |
|---|-----|------|
| 1 | `docker exec` 必须带 `-i`，否则管道 SQL 被**静默丢弃** | 课 6/7/10/12 |
| 2 | `SET` 会话变量**跨连接失效**，必须塞进同一连接 | 课 8 |
| 3 | **不能用 `COUNT(*)` 验证数据可查**——走 FE 元数据优化，不扫 BE | 课 9/12 |
| 4 | `SHOW DATA` 紧跟 INSERT 返回 0，需等约 45 秒统计刷新 | 课 6 |
| 5 | S3 操作对 MinIO 必须加 `'use_path_style'='true'` | 课 6/11/12 |
| 6 | `CREATE/DROP REPOSITORY` **不支持** `IF NOT EXISTS` / `IF EXISTS` | 课 11 |
| 7 | `RESTORE` 的 `replication_num` 默认 3 **不沿用原表**，失败信息藏在 `SHOW RESTORE` | 课 11 |
| 8 | `SHOW BACKUP` / `SHOW RESTORE` 取最新作业要 `tail -1` | 课 11 |
| 9 | `ALTER TABLE ... ADD COLUMN` / `DROP COLUMN` **都不支持 `IF EXISTS`** | Phase 3 实测 |
| 10 | `MODIFY COLUMN` 不能改带 `DEFAULT` 值的列——**所以加列时别写 DEFAULT** | 课 11 + Phase 3 实测 |
| 11 | `SHOW MATERIALIZED VIEWS` 报语法错误，只能用 `SHOW CREATE MATERIALIZED VIEW <name>` | 课 8 |
| 12 | 异步 MV 透明改写**不稳定**，判断要看 EXPLAIN 的 MATERIALIZATIONS 段 | 课 8 + Phase 3 实测 |
| 13 | 测延迟必须先剥离连接开销（单连接串行发 N 条，别用 N 次 `docker exec`） | 课 12 |
| 14 | Workload Group 的 `memory_low_watermark` 默认 75%，配水位要成对 | 课 10 |
| 15 | 一个 Compute Group 下最多 15 个 Workload Group | 课 10 |
| 16 | **`order_id` 只在当天唯一**，`WHERE order_id=xxx` 的"单行"DELETE 实际删 331 行且不报错 | **Phase 3 实测（最危险）** |
| 17 | **分区 MV 刷不出数据**：建表/刷新/分区全正常，只有 SELECT 才发现是 0 行 | Phase 3 实测 |
| 18 | **`information_schema.partitions` 没有 `REPLICATION_NUM` 列**，查副本数要用 `SHOW CREATE TABLE` | Phase 3 实测 |
| 19 | **`SHOW RESTORE` 不能用 awk 按列号取 Status**：Info 列含 `\n` 转义 JSON 会打乱列位置，用 `grep -oE` | Phase 3 实测 |
| 20 | Kafka 在**独立容器** `doris-kafka`，broker 是 `kafka:9092`，producer 脚本不在 `doris-learn` 里 | Phase 3 实测 |

> 🔥 **四个静默失败**（命令返回成功、数据其实错了）是本项目最贵的收获，
> 全部实测复现并修复，详见各 Task 文档：
>
> | # | 静默失败 | 出处 |
> |---|---------|------|
> | 1 | `order_id` 撞车丢数据（58%） | Task 2 |
> | 2 | 维表凭空编造，INNER JOIN 丢 4 个省 | Task 1 / Task 3 |
> | 3 | `RESTORE` 默认 3 副本，恢复表是空的 | Task 4 |
> | 4 | "单行" DELETE 实际删 331 行 | **Task 5** |

---

## 🚀 开始

按顺序执行，每个 Task 文档里都有完整的、可直接复制运行的命令：

```bash
# 前置：确认集群活着
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW BACKENDS\G" | grep -E "Alive:|HeartbeatPort:"

# Task 1：需求与建模
bash assets/phase3-task1-setup.sh
```

---

## 📚 与 12 课的映射

| 课 | 知识 | 在 Phase 3 哪里用到 |
|----|------|-------------------|
| 课 1 | OLAP vs OLTP、列存 | Task 1 需求分析与列存收益复现 |
| 课 2 | 集群部署 | Task 4 集群健康检查 |
| 课 3 | 三种表模型 | Task 1 四层建模选型 |
| 课 4 | 分区分桶 | Task 1 分区设计与 Task 3 裁剪验证 |
| 课 5 | 索引 / Rollup / MV | Task 3 加速三板斧 |
| 课 6 | 数据导入全家桶 | Task 2 双链路接入 |
| 课 7 | 查询引擎 / Profile | Task 3 慢查询定位 |
| 课 8 | Join / 高级 SQL | Task 3 多表关联与窗口函数 |
| 课 9 | 副本 / 扩缩容 | Task 4 副本策略 |
| 课 10 | Workload Group | Task 4 资源隔离 |
| 课 11 | Schema Change / 备份 | Task 4 变更与备份 |
| 课 12 | 选型 / 边界 | Task 5 验收与边界 |
