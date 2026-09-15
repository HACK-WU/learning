# PostgreSQL 17 官方文档 · 路由表

> 起始 URL：https://www.postgresql.org/docs/17/index.html
> **我要做什么 → 去查哪一页（含锚点）**。查不到再回 [`../INDEX.md`](../INDEX.md) 换分区。
> 全部链接经 `curl` 实测 HTTP 200（核查于 2026-09）。

---

## 我要开始备份/恢复

| 我要… | 去哪一页 | 备注 |
|-------|----------|------|
| 搞清逻辑 / 物理 / PITR 三者的边界 | [`backup.html`](https://www.postgresql.org/docs/17/backup.html) | 25.1 总览，先读这页 |
| 选 `pg_dump` 的输出格式 | [`app-pgdump.html`](https://www.postgresql.org/docs/17/app-pgdump.html) | 四格式 + `-j` 只认 directory + 压缩算法表 |
| 备整个集群（含角色 / 表空间） | [`app-pg-dumpall.html`](https://www.postgresql.org/docs/17/app-pg-dumpall.html) | `pg_dump` **不含** roles/tablespaces |
| 选择性恢复 / 只恢复某张表 | [`app-pgrestore.html`](https://www.postgresql.org/docs/17/app-pgrestore.html) | `-l`/`-L`/`-t`/`-e`/`--clean --if-exists` |
| 拍一份物理基础备份 | [`app-pgbasebackup.html`](https://www.postgresql.org/docs/17/app-pgbasebackup.html) | `-F` 默认 plain、`-X` 默认 stream、`-R` |
| 校验物理备份没坏 | [`app-pgverifybackup.html`](https://www.postgresql.org/docs/17/app-pgverifybackup.html) | **须对解包后目录**跑 |
| 做增量物理备份（PG 17+） | [`app-pgcombinebackup.html`](https://www.postgresql.org/docs/17/app-pgcombinebackup.html) | 配 `pg_basebackup --incremental` |
| 开 WAL 归档 / 学「回到任意时刻」 | [`continuous-archiving.html`](https://www.postgresql.org/docs/17/continuous-archiving.html) | 25.3，含恢复十步 + timeline |
| 查 `archive_mode` / `restore_command` 等参数 | [`runtime-config-wal.html`](https://www.postgresql.org/docs/17/runtime-config-wal.html) | 19.5；恢复目标看锚点 `#RECOVERY-TARGET` |
| 搞清楚 PG 12 为什么删了 `recovery.conf` | [`/docs/12/release-12.html`](https://www.postgresql.org/docs/12/release-12.html) | 发布说明**不在 17 路径下** |

详见 [`topics/backup-recovery.md`](topics/backup-recovery.md)。

## 我要做复制 / 高可用

| 我要… | 去哪一页 |
|-------|----------|
| 先看复制与 HA 的全景 | [`high-availability.html`](https://www.postgresql.org/docs/17/high-availability.html) |
| 日志传送（warm standby） | [`warm-standby.html`](https://www.postgresql.org/docs/17/warm-standby.html) |
| 只读热备（hot standby） | [`hot-standby.html`](https://www.postgresql.org/docs/17/hot-standby.html) |
| 逻辑复制 | [`logical-replication.html`](https://www.postgresql.org/docs/17/logical-replication.html) |
| 建/改发布订阅 | [`sql-createsubscription.html`](https://www.postgresql.org/docs/17/sql-createsubscription.html) |
| PG 17 从物理备份直接建订阅者 | [`app-pgcreatesubscriber.html`](https://www.postgresql.org/docs/17/app-pgcreatesubscriber.html) |
| 复制相关 GUC（槽 / sender / 延迟） | [`runtime-config-replication.html`](https://www.postgresql.org/docs/17/runtime-config-replication.html) |
| 看复制协议报文细节 | [`protocol-replication.html`](https://www.postgresql.org/docs/17/protocol-replication.html) |
| 收 WAL / 追时间线 | [`app-pgreceivewal.html`](https://www.postgresql.org/docs/17/app-pgreceivewal.html) / [`app-pgrewind.html`](https://www.postgresql.org/docs/17/app-pgrewind.html) |
| WAL 文件的内部结构 | [`wal-internals.html`](https://www.postgresql.org/docs/17/wal-internals.html) / [`wal.html`](https://www.postgresql.org/docs/17/wal.html) |

详见 [`topics/replication-ha.md`](topics/replication-ha.md)。

## 我要监控 / 调性能

| 我要… | 去哪一页 |
|-------|----------|
| 监控该看什么（标准清单） | [`monitoring.html`](https://www.postgresql.org/docs/17/monitoring.html) |
| 找 `pg_stat_*` 视图与字段定义 | [`monitoring-stats.html`](https://www.postgresql.org/docs/17/monitoring-stats.html) |
| 长命令的进度条（VACUUM / CREATE INDEX） | [`progress-reporting.html`](https://www.postgresql.org/docs/17/progress-reporting.html) |
| 读 `EXPLAIN` 输出 | [`using-explain.html`](https://www.postgresql.org/docs/17/using-explain.html) |
| 优化器怎么估算代价 | [`planner-optimizer.html`](https://www.postgresql.org/docs/17/planner-optimizer.html) / [`index-cost-estimation.html`](https://www.postgresql.org/docs/17/index-cost-estimation.html) |
| 并行查询怎么算 worker 数 | [`parallel-query.html`](https://www.postgresql.org/docs/17/parallel-query.html) |
| 为什么表会膨胀 / 怎么清 | [`routine-vacuuming.html`](https://www.postgresql.org/docs/17/routine-vacuuming.html) / [`sql-vacuum.html`](https://www.postgresql.org/docs/17/sql-vacuum.html) |
| autovacuum 参数默认值 | [`runtime-config-autovacuum.html`](https://www.postgresql.org/docs/17/runtime-config-autovacuum.html) |
| 手动收集统计信息 | [`sql-analyze.html`](https://www.postgresql.org/docs/17/sql-analyze.html) |
| 看磁盘用量 / 大对象 | [`diskusage.html`](https://www.postgresql.org/docs/17/diskusage.html) / [`lo.html`](https://www.postgresql.org/docs/17/lo.html) |

详见 [`topics/observability.md`](topics/observability.md)。

## 我要管权限 / 装扩展 / 升级

| 我要… | 去哪一页 |
|-------|----------|
| 建角色、给权限 | [`sql-createrole.html`](https://www.postgresql.org/docs/17/sql-createrole.html) / [`sql-grant.html`](https://www.postgresql.org/docs/17/sql-grant.html) / [`sql-revoke.html`](https://www.postgresql.org/docs/17/sql-revoke.html) |
| 权限模型总论 | [`ddl-priv.html`](https://www.postgresql.org/docs/17/ddl-priv.html) / [`user-manag.html`](https://www.postgresql.org/docs/17/user-manag.html) / [`role-attributes.html`](https://www.postgresql.org/docs/17/role-attributes.html) |
| 客户端认证（pg_hba / 各类认证法） | [`client-authentication.html`](https://www.postgresql.org/docs/17/client-authentication.html) / [`auth-methods.html`](https://www.postgresql.org/docs/17/auth-methods.html) / [`auth-password.html`](https://www.postgresql.org/docs/17/auth-password.html) / [`auth-ldap.html`](https://www.postgresql.org/docs/17/auth-ldap.html) / [`auth-cert.html`](https://www.postgresql.org/docs/17/auth-cert.html) |
| 开 SSL / 选加密方式 | [`ssl-tcp.html`](https://www.postgresql.org/docs/17/ssl-tcp.html) / [`encryption-options.html`](https://www.postgresql.org/docs/17/encryption-options.html) |
| 写自己的扩展 | [`extend.html`](https://www.postgresql.org/docs/17/extend.html) / [`bgworker.html`](https://www.postgresql.org/docs/17/bgworker.html) / [`tableam.html`](https://www.postgresql.org/docs/17/tableam.html) / [`custom-rmgr.html`](https://www.postgresql.org/docs/17/custom-rmgr.html) |
| 查官方附带模块清单 | [`contrib.html`](https://www.postgresql.org/docs/17/contrib.html) |
| 预读表进 OS cache | [`pgprewarm.html`](https://www.postgresql.org/docs/17/pgprewarm.html) |
| 大版本升级 | [`pgupgrade.html`](https://www.postgresql.org/docs/17/pgupgrade.html) |
| 校验数据校验和 | [`app-pgchecksums.html`](https://www.postgresql.org/docs/17/app-pgchecksums.html) |

详见 [`topics/security-extensions.md`](topics/security-extensions.md)。

## 我要查参数 / 用工具 / 读锁

| 我要… | 去哪一页 |
|-------|----------|
| 参数怎么设、什么时候生效 | [`config-setting.html`](https://www.postgresql.org/docs/17/config-setting.html) |
| 改参数（含 `ALTER SYSTEM`） | [`sql-altersystem.html`](https://www.postgresql.org/docs/17/sql-altersystem.html) |
| 连接 / 资源 / 日志 / 统计 四类参数 | [`runtime-config-connection.html`](https://www.postgresql.org/docs/17/runtime-config-connection.html) · [`runtime-config-resource.html`](https://www.postgresql.org/docs/17/runtime-config-resource.html) · [`runtime-config-logging.html`](https://www.postgresql.org/docs/17/runtime-config-logging.html) · [`runtime-config-statistics.html`](https://www.postgresql.org/docs/17/runtime-config-statistics.html) |
| 核客户端参数（含超时族） | [`runtime-config-client.html`](https://www.postgresql.org/docs/17/runtime-config-client.html) |
| 用 psql / pg_ctl / pg_controldata | [`app-psql.html`](https://www.postgresql.org/docs/17/app-psql.html) · [`app-pg-ctl.html`](https://www.postgresql.org/docs/17/app-pg-ctl.html) · [`app-pgcontroldata.html`](https://www.postgresql.org/docs/17/app-pgcontroldata.html) · [`app-pg-isready.html`](https://www.postgresql.org/docs/17/app-pg-isready.html) |
| 压测 / 看 WAL 内容 / 重置 WAL | [`pgbench.html`](https://www.postgresql.org/docs/17/pgbench.html) · [`pgwaldump.html`](https://www.postgresql.org/docs/17/pgwaldump.html) · [`app-pgresetwal.html`](https://www.postgresql.org/docs/17/app-pgresetwal.html) |
| 读事务隔离级别（含官方矩阵） | [`transaction-iso.html`](https://www.postgresql.org/docs/17/transaction-iso.html) |
| 读锁（表级 / 行级 / 咨询锁） | [`explicit-locking.html`](https://www.postgresql.org/docs/17/explicit-locking.html) |
| 读 MVCC 与快照 | [`mvcc.html`](https://www.postgresql.org/docs/17/mvcc.html) / [`routine-vacuuming.html`](https://www.postgresql.org/docs/17/routine-vacuuming.html) |
| 查系统管理函数（含 `pg_locks` 等） | [`functions-admin.html`](https://www.postgresql.org/docs/17/functions-admin.html) |
| 查错误码（SQLSTATE） | [`errcodes-appendix.html`](https://www.postgresql.org/docs/17/errcodes-appendix.html) |
| 查索引类型与原理 | [`indexes.html`](https://www.postgresql.org/docs/17/indexes.html) / [`sql-createindex.html`](https://www.postgresql.org/docs/17/sql-createindex.html) |
| 用 `COPY` 批量导入导出 | [`sql-copy.html`](https://www.postgresql.org/docs/17/sql-copy.html) |
| 查 SQL 语法总入口 | [`sql-syntax.html`](https://www.postgresql.org/docs/17/sql-syntax.html) |
