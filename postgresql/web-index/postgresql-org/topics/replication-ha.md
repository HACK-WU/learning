# 分区 · 复制与高可用

> 服务课次：**课 15 复制与高可用**（预收集，2026-09-10 备课期建立）
> 全部链接经 `curl` 实测 HTTP 200（核查于 2026-09）

---

## 1. 全景

| 我要… | 页面 | 备注 |
|-------|------|------|
| 先看复制 / 负载均衡 / HA 的全景 | [`high-availability.html`](https://www.postgresql.org/docs/17/high-availability.html)（26.1） | 26.1 讲清"日志传送 / 流复制 / 逻辑复制"三条路的取舍 |
| 日志传送（warm standby） | [`warm-standby.html`](https://www.postgresql.org/docs/17/warm-standby.html)（26.2） | 只读不可查 → 可查的分界线 |
| 热备（hot standby，可读） | [`hot-standby.html`](https://www.postgresql.org/docs/17/hot-standby.html)（26.4） | `hot_standby_feedback` / `max_standby_*_delay` / 冲突取消查询 |
| 故障切换（promote） | [`app-pg-ctl.html`](https://www.postgresql.org/docs/17/app-pg-ctl.html) | `pg_ctl promote -D <datadir>`；也可以删掉 `standby.signal` |
| 被提升后重新追回原主 | [`app-pgrewind.html`](https://www.postgresql.org/docs/17/app-pgrewind.html) | `pg_rewind` —— 避免重新 clone 整个集群 |
| 收 WAL 到本地（日志传送） | [`app-pgreceivewal.html`](https://www.postgresql.org/docs/17/app-pgreceivewal.html) | `pg_receivewal` |

## 2. 页面锚点

| 主题 | 锚点 |
|------|------|
| 设置主库（`wal_level` / `max_wal_senders` / `pg_hba`） | `warm-standby.html#WARM-STANDBY-PRIMARY` |
| 设置从库（`primary_conninfo` / `restore_command`） | `warm-standby.html#WARM-STANDBY-STANDBY` |
| 流复制协议 | [`protocol-replication.html`](https://www.postgresql.org/docs/17/protocol-replication.html)（52.4） |
| 复制相关 GUC 全家 | [`runtime-config-replication.html`](https://www.postgresql.org/docs/17/runtime-config-replication.html)（19.6） |
| WAL 内部结构（讲义配图素材） | [`wal-internals.html`](https://www.postgresql.org/docs/17/wal-internals.html) / [`wal.html`](https://www.postgresql.org/docs/17/wal.html) |

## 3. 必查的事实点（课 15 讲义前须联网核实）

| # | 待核实 | 去哪查 |
|---|--------|--------|
| 1 | `wal_level` 三值（`minimal`/`replica`/`logical`）各支持什么，`logical` 的额外代价（WAL 体积、`max_replication_slots`） | `runtime-config-wal.html` |
| 2 | **复制槽**：`max_replication_slots` 默认值、槽不消费会**撑爆磁盘**、`pg_replication_slots` 字段 | `runtime-config-replication.html` + [`monitoring-stats.html`](https://www.postgresql.org/docs/17/monitoring-stats.html) |
| 3 | **同步 vs 异步**：`synchronous_commit` 各档（`local`/`on`/`remote_write`/`remote_apply`）的延迟与安全权衡；`synchronous_standby_names` 的 `ANY n (...)` 语法 | `runtime-config-wal.html#RUNTIME-CONFIG-WAL-SETTINGS` |
| 4 | **主从延迟三个 lag**：`pg_stat_replication` 的 `write_lag` / `flush_lag` / `replay_lag` 各自语义差异（官方明确三者不同） | `monitoring-stats.html` |
| 5 | 触发式故障切换（`pg_ctl promote` / `pg_promote()` / `trigger_file` 已废弃） | `app-pg-ctl.html` + `functions-admin.html` |
| 6 | PG 17 新增：`pg_createsubscriber`（从物理备份直接建逻辑订阅者）、逻辑复制 failover | [`app-pgcreatesubscriber.html`](https://www.postgresql.org/docs/17/app-pgcreatesubscriber.html) + [`release-17.html`](https://www.postgresql.org/docs/17/release-17.html) |

## 4. 逻辑复制

| 我要… | 页面 |
|-------|------|
| 逻辑复制总论与限制 | [`logical-replication.html`](https://www.postgresql.org/docs/17/logical-replication.html) / [`logical-replication-restrictions.html`](https://www.postgresql.org/docs/17/logical-replication-restrictions.html) |
| 建发布 / 订阅 | [`sql-createsubscription.html`](https://www.postgresql.org/docs/17/sql-createsubscription.html) |
| 逻辑复制相关参数（`max_logical_replication_workers` 等） | [`logical-replication-config.html`](https://www.postgresql.org/docs/17/logical-replication-config.html) |
| 逻辑解码（自己写消费程序） | [`logicaldecoding.html`](https://www.postgresql.org/docs/17/logicaldecoding.html) |

## 5. 与本课相关的既有资产

- 课 14 的 `pg_basebackup -R -X stream` 产物 → 直接就是一台从库的起点（`standby.signal` + `primary_conninfo` 自动写好）
- 课 14 的 `/tmp/archive` WAL 归档目录 → 可改成从库的 `restore_command` 源（日志传送路线）
- 课 13 的锁与 `pg_stat_activity` 观察手法 → 用于观察从库恢复冲突（`pg_stat_database_conflicts`）

## 6. 相关分区

- 备份与恢复（本课的前置）→ [`backup-recovery.md`](backup-recovery.md)
- 监控视图（看复制延迟）→ [`observability.md`](observability.md)
- 参数改动方式与生效级别 → [`server-config-and-sql.md`](server-config-and-sql.md)
