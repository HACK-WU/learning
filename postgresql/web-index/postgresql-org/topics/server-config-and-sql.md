# 分区 · 参数体系与通用 SQL / 并发

> 服务课次：**课 1–17 通用**（参数怎么改、工具在哪、锁与隔离怎么查、错误码去哪找）
> 全部链接经 `curl` 实测 HTTP 200（核查于 2026-09）

---

## 1. 参数体系（改参数的三种方式与生效级别）

| 我要… | 页面 | 备注 |
|-------|------|------|
| 搞清参数怎么设、何时生效 | [`config-setting.html`](https://www.postgresql.org/docs/17/config-setting.html)（19.1） | **官方四档生效级别**：`postmaster`（改后须重启）/ `sighup`（reload 即可）/ `user`（会话内可改）/ `internal`。讲义里说"改了要重启"必须来这页核实 |
| 用 SQL 改全局参数 | [`sql-altersystem.html`](https://www.postgresql.org/docs/17/sql-altersystem.html) | `ALTER SYSTEM SET ...` 写进 `postgresql.auto.conf`（不是 `postgresql.conf`） |
| 会话/事务级临时改 | [`sql-set.html`](https://www.postgresql.org/docs/17/sql-set.html) | `SET` / `SET LOCAL` / `RESET` / `set_config()` |

## 2. 五个 runtime-config 页（按用途分）

| 用途 | 页面 | 课程相关参数 |
|------|------|-------------|
| **连接** | [`runtime-config-connection.html`](https://www.postgresql.org/docs/17/runtime-config-connection.html)（19.3） | `max_connections` / `listen_addresses` / `port` / `unix_socket_directories` |
| **资源** | [`runtime-config-resource.html`](https://www.postgresql.org/docs/17/runtime-config-resource.html)（19.4） | `shared_buffers` / `work_mem` / `maintenance_work_mem` / `max_worker_processes` / `max_parallel_workers` / `effective_cache_size` |
| **WAL** | [`runtime-config-wal.html`](https://www.postgresql.org/docs/17/runtime-config-wal.html)（19.5） | `wal_level` / `fsync` / `synchronous_commit` / `full_page_writes` / `archive_mode` / `archive_command` / **恢复目标家族** |
| **复制** | [`runtime-config-replication.html`](https://www.postgresql.org/docs/17/runtime-config-replication.html)（19.6） | `max_wal_senders` / `max_replication_slots` / `wal_keep_size` / `synchronous_standby_names` |
| **日志** | [`runtime-config-logging.html`](https://www.postgresql.org/docs/17/runtime-config-logging.html)（19.8） | `log_min_duration_statement` / `log_line_prefix` / `log_lock_waits` / `log_statement` |
| **统计** | [`runtime-config-statistics.html`](https://www.postgresql.org/docs/17/runtime-config-statistics.html)（19.9） | `track_counts` / `track_io_timing` / `track_functions` |
| **autovacuum** | [`runtime-config-autovacuum.html`](https://www.postgresql.org/docs/17/runtime-config-autovacuum.html)（19.10） | `autovacuum` / `autovacuum_naptime` / `autovacuum_vacuum_scale_factor` |
| **客户端** | [`runtime-config-client.html`](https://www.postgresql.org/docs/17/runtime-config-client.html)（19.12） | `statement_timeout` / `lock_timeout` / `idle_in_transaction_session_timeout` / `idle_session_timeout` / **`transaction_timeout`（PG 17 新增）** |

**课程反复用到的默认值锚点**：
- `runtime-config-wal.html#RUNTIME-CONFIG-WAL-SETTINGS`（`wal_level` 默认 `replica`）
- `runtime-config-replication.html#RUNTIME-CONFIG-REPLICATION-SENDER`（`max_wal_senders` 默认 10）
- `runtime-config-client.html#RUNTIME-CONFIG-CLIENT-STATEMENT`

## 3. 服务器程序与运维工具

| 工具 | 页面 | 用途 |
|------|------|------|
| `psql` | [`app-psql.html`](https://www.postgresql.org/docs/17/app-psql.html) | 唯一官方客户端；`\d` / `\x` / `\timing` / `\copy` / `-v` 变量 |
| `pg_ctl` | [`app-pg-ctl.html`](https://www.postgresql.org/docs/17/app-pg-ctl.html) | `start` / `stop` / `restart` / `reload` / **`promote`** / `status` |
| `pg_controldata` | [`app-pgcontroldata.html`](https://www.postgresql.org/docs/17/app-pgcontroldata.html) | 看集群控制信息（含"下一个 checkpoint 前不能恢复"边界） |
| `pg_isready` | [`app-pg-isready.html`](https://www.postgresql.org/docs/17/app-pg-isready.html) | 健康检查探测（返回码可判三态） |
| `pg_resetwal` | [`app-pgresetwal.html`](https://www.postgresql.org/docs/17/app-pgresetwal.html) | ⚠️ **最后手段**，会丢数据 |
| `pg_waldump` | [`pgwaldump.html`](https://www.postgresql.org/docs/17/pgwaldump.html) | 读 WAL 文件内容（调试利器） |
| `pgbench` | [`pgbench.html`](https://www.postgresql.org/docs/17/pgbench.html) | 官方压测工具 |

> ⚠️ **命名的坑**（实测验证）：`pgupgrade.html`（不是 `app-pgupgrade.html`）、`pgbench.html`（不是 `app-pgbench.html`）、`pgwaldump.html`（不是 `app-pg-waldump.html`）、`app-pgresetwal.html`（不是 `app-pg-resetwal.html`）、`app-pg-dumpall.html`（是连字符，不是 `app-pgdumpall.html`）、`app-pgreceivewal.html`（不是 `app-pg-receivewal.html`）。

## 4. 并发：事务 / MVCC / 锁

| 我要… | 页面 | 课程出处 |
|-------|------|----------|
| 四种隔离级别 + 官方 Table 13.1 矩阵 | [`transaction-iso.html`](https://www.postgresql.org/docs/17/transaction-iso.html)（13.2） | **课 11** |
| MVCC 与快照、可见性规则 | [`mvcc.html`](https://www.postgresql.org/docs/17/mvcc.html)（13.1） | **课 12** |
| 表级锁 8 种 + 行级锁 4 种 + 冲突矩阵（Table 13.2 / 13.3） | [`explicit-locking.html`](https://www.postgresql.org/docs/17/explicit-locking.html)（13.3） | **课 13** |
| 死锁检测与排查 | `explicit-locking.html#LOCKING-DEADLOCKS` | **课 13** |
| 咨询锁（advisory lock） | `functions-admin.html#FUNCTIONS-ADVISORY-LOCKS` | **课 13** |
| 死元组清理与 XID 回卷 | [`routine-vacuuming.html`](https://www.postgresql.org/docs/17/routine-vacuuming.html)（24.1） | **课 12** |
| `pg_locks` / `pg_blocking_pids()` / 会话管理函数 | [`functions-admin.html`](https://www.postgresql.org/docs/17/functions-admin.html)（9.27） | **课 13** |
| 超时四件套（`statement` / `lock` / `idle_in_transaction_session` / `transaction`） | [`runtime-config-client.html`](https://www.postgresql.org/docs/17/runtime-config-client.html) | **课 11 / 课 13** |

## 5. 错误码与 SQL 基础

| 我要… | 页面 |
|-------|------|
| 查 SQLSTATE 含义（`40P01` / `40001` / `55P03` / `23505` ...） | [`errcodes-appendix.html`](https://www.postgresql.org/docs/17/errcodes-appendix.html)（附录 A） |
| SQL 语法总入口 | [`sql-syntax.html`](https://www.postgresql.org/docs/17/sql-syntax.html) |
| 系统管理函数（配置、统计、锁、快照、备份控制） | [`functions-admin.html`](https://www.postgresql.org/docs/17/functions-admin.html)（9.27） |
| `COPY` 批量导入导出 | [`sql-copy.html`](https://www.postgresql.org/docs/17/sql-copy.html) |
| `VACUUM` 语法 | [`sql-vacuum.html`](https://www.postgresql.org/docs/17/sql-vacuum.html) |
| `EXPLAIN` 语法 | [`sql-explain.html`](https://www.postgresql.org/docs/17/sql-explain.html) |

## 6. 课程实测环境基线（写讲义时对齐）

| 项 | 值 |
|----|-----|
| 版本 | **PostgreSQL 17.11**（Debian 17.11-1.pgdg13+2，Docker `postgres:17`） |
| 容器名 / 端口 | `pg17` / **5433**（5432 被另一项目 `docker-db-1` 占用） |
| `docker` CLI | `/usr/local/bin`，需 `export PATH="/usr/local/bin:$PATH"` |
| 主库 | `order_service`（课 14 时 **661 MB**，数据目录 3.0 G）/ `finance` schema 24 表 |
| 已启扩展 | `pageinspect` / `pgstattuple` / `pg_trgm` / `pg_stat_statements`（需 `shared_preload_libraries` + 重启） |
| 容器内注意 | 无 `file` / `python3`（用 `od -c` / `xxd`）；`createdb`/`dropdb`/`psql` **必须带 `-U postgres`** |

## 7. 相关分区

- 备份与恢复 → [`backup-recovery.md`](backup-recovery.md)
- 复制与高可用 → [`replication-ha.md`](replication-ha.md)
- 可观测性（监控 / 计划 / 清理）→ [`observability.md`](observability.md)
- 安全与扩展 → [`security-extensions.md`](security-extensions.md)
