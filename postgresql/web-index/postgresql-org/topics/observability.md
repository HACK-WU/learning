# 分区 · 可观测性（监控 / 计划 / 清理）

> 服务课次：课 9《执行计划》、课 10《慢查询优化实战》、课 12《MVCC 与并发控制》、**课 16《监控与性能》**（预收集）
> 全部链接经 `curl` 实测 HTTP 200（核查于 2026-09）

---

## 1. 监控标准与视图族

| 我要… | 页面 | 备注 |
|-------|------|------|
| 监控该看什么（官方标准清单） | [`monitoring.html`](https://www.postgresql.org/docs/17/monitoring.html)（27.1） | 27.1.1 UNIX 工具 → 27.1.2 `pg_stat_*` → 27.1.3 日志 → 27.1.4 进程状态 → 27.1.5 磁盘 |
| 找**任一** `pg_stat_*` 视图的字段定义 | [`monitoring-stats.html`](https://www.postgresql.org/docs/17/monitoring-stats.html)（27.2） | 本页是 `pg_stat_activity` / `pg_stat_replication` / `pg_stat_user_tables` / `pg_stat_statements` 收录位 等的权威定义处。**查字段先来这里** |
| 长命令的进度（VACUUM / CREATE INDEX / COPY / 备份） | [`progress-reporting.html`](https://www.postgresql.org/docs/17/progress-reporting.html)（27.4） | `pg_stat_progress_*` 家族 |
| 统计信息收集器参数 | [`runtime-config-statistics.html`](https://www.postgresql.org/docs/17/runtime-config-statistics.html)（19.9） | `track_counts` / `track_io_timing` / `track_functions` / `stats_temp_directory` |
| 慢查询日志 | [`runtime-config-logging.html`](https://www.postgresql.org/docs/17/runtime-config-logging.html)（19.8） | `log_min_duration_statement` 默认 **-1**（关闭）；`log_line_prefix` / `log_lock_waits` |

## 2. 语句级诊断

| 我要… | 页面 / 锚点 |
|-------|------------|
| 读 `EXPLAIN` 输出 | [`using-explain.html`](https://www.postgresql.org/docs/17/using-explain.html)（14.1） |
| 读 cost 与行数估算 | `planner-optimizer.html#PLANNER-OPTIMIZER-STATISTICS` |
| 优化器怎么算代价 | [`planner-optimizer.html`](https://www.postgresql.org/docs/17/planner-optimizer.html)（14.4） |
| 索引代价怎么估 | [`index-cost-estimation.html`](https://www.postgresql.org/docs/17/index-cost-estimation.html)（14.4.2） |
| 并行查询怎么算 worker 数（`min_parallel_table_scan_size` / `parallel_setup_cost`） | [`parallel-query.html`](https://www.postgresql.org/docs/17/parallel-query.html)（15） |
| 性能调优总清单 | [`performance-tips.html`](https://www.postgresql.org/docs/17/performance-tips.html)（14） |
| `ANALYZE` 与统计信息 | [`sql-analyze.html`](https://www.postgresql.org/docs/17/sql-analyze.html) |
| `pg_stat_statements` 的 `max` / `track` 默认值 | `runtime-config-statistics.html#GUC-PG-STAT-STATEMENTS` |

**课程已有的观察手法**（课 9–10 沉淀）：
- `SET enable_nestloop/hashjoin/mergejoin/hashagg = off` 做算子对照
- `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`；`Rows Removed by Filter` 只在有行被过滤时出现
- `pg_stat_statements` 需 `shared_preload_libraries` + 重启；`max` 只能启动时设

## 3. VACUUM / 膨胀 / 磁盘

| 我要… | 页面 |
|-------|------|
| 为什么必须 VACUUM（含 XID 回卷） | [`routine-vacuuming.html`](https://www.postgresql.org/docs/17/routine-vacuuming.html)（24.1） |
| `VACUUM` / `VACUUM FULL` 语法与选项 | [`sql-vacuum.html`](https://www.postgresql.org/docs/17/sql-vacuum.html) |
| autovacuum 参数与默认值（触发公式） | [`runtime-config-autovacuum.html`](https://www.postgresql.org/docs/17/runtime-config-autovacuum.html)（19.10） |
| 表实际占多少磁盘 / 找大表 | [`diskusage.html`](https://www.postgresql.org/docs/17/diskusage.html)（24.2） |
| 大对象（lo） | [`lo.html`](https://www.postgresql.org/docs/17/lo.html) |
| 预读表进 OS cache | [`pgprewarm.html`](https://www.postgresql.org/docs/17/pgprewarm.html) |

## 4. 索引原理（课 8 已用，课 16 会回指）

| 我要… | 页面 |
|-------|------|
| 索引类型总论（B-Tree / Hash / GiST / SP-GiST / GIN / BRIN） | [`indexes.html`](https://www.postgresql.org/docs/17/indexes.html)（11） |
| `CREATE INDEX` 全选项（含 `CONCURRENTLY` / `INCLUDE` / `WHERE`） | [`sql-createindex.html`](https://www.postgresql.org/docs/17/sql-createindex.html) |

## 5. 必查的事实点（课 16 讲义前须联网核实）

| # | 待核实 | 去哪查 |
|---|--------|--------|
| 1 | 官方推荐的"关键指标"清单有哪些，各对应哪个视图 | `monitoring.html` |
| 2 | `pg_stat_activity` 各列含义 + `state` 取值 + `wait_event_type` / `wait_event` 分类 | `monitoring-stats.html` |
| 3 | 统计视图的**延迟问题**（`pg_stat_force_next_flush()` / 计数器重置） | `monitoring-stats.html` + `functions-admin.html` |
| 4 | `pg_stat_statements` 的 `total_exec_time` **不含** planning time（要 `total_plan_time`） | `runtime-config-statistics.html#GUC-PG-STAT-STATEMENTS` |
| 5 | 三种 Join 的官方代价模型表述（Hash Join 是 **right relation** 建表，不是"小的那个"） | `planner-optimizer.html` |
| 6 | `auto_explain` 与 `log_min_duration_statement` 的定位分工 | `runtime-config-logging.html` + `contrib.html` |
| 7 | `random_page_cost` 在 SSD 上该取多少（官方默认 4.0 的前提是什么） | [`runtime-config-query.html`](https://www.postgresql.org/docs/17/runtime-config-query.html) |

## 6. 相关分区

- 备份与恢复（备份耗时 / WAL 生成量与监控相关）→ [`backup-recovery.md`](backup-recovery.md)
- 参数改动方式与生效级别 → [`server-config-and-sql.md`](server-config-and-sql.md)
- 权限（谁有权看 `pg_stat_*`）→ [`security-extensions.md`](security-extensions.md)
