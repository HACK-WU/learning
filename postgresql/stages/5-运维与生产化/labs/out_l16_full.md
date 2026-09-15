# 课 16 实验原始输出汇总

> 环境：PostgreSQL 17.11（Docker `postgres:17`）/ macOS arm64 / 主库 `pg17`（5433）/ 从库 `pg17-standby`（5435）。
> 时间：2026-09-11。脚本：[`l16_labs.sh`](l16_labs.sh)。

## A 组 · 巡检五件套

### A-1 连接与会话构成

```text
 state  | count          backend_type              | count
--------+-------        ---------------------------+-------
        |     6          client backend            |     1
 active |     2          walwriter                 |     1
                       walsender                  |     1     ← 课 15 的从库
                       autovacuum launcher        |     1
                       logical replication launcher |   1
                       background writer          |     1
                       archiver                   |     1
                       checkpointer               |     1
```

> state 为 NULL 的是后台进程（它们没有"客户端会话状态"）。

### A-2 库级累计 + 缓存命中率（真实运行 5 天的课程库）

```text
    datname    | xact_commit | xact_rollback | deadlocks | blks_hit | blks_read | 命中率_pct
 order_service |        7489 |           331 |         4 | 17843907 |    281432 |      98.45
```

- 命中率 98.45% **低于 99% 经验线**——容器 8GB VM 与 ES/ELK 共享，缓存压力真实；"阈值是参考不是教条"
- `deadlocks=4`：课 13 死锁实验的历史痕迹——统计视图记得每一次实验

### A-3 WAL 与 checkpoint（⚠ PG 17 列名全改）

```text
 wal_records | wal总量 | wal_buffers_full
    27874774 | 3707 MB |           394292

 num_timed | num_requested | buffers_written        ← 旧名 checkpoints_timed/requested 已不存在
       604 |            21 |           71404          （21 次请求式 = 历次手工 CHECKPOINT 实验）

 buffers_clean | maxwritten_clean | buffers_alloc
         34773 |              226 |        280176
```

### A-4 表级 TOP

```text
   relname   | seq_scan | idx_scan | n_live_tup | n_dead_tup |        last_autovacuum
 orders_big  |       20 |      333 |    1000000 |        100 |
 note_search |       16 |        3 |     300000 |          0 | 2026-09-08 14:19:21.628406+00
 cast_demo   |        7 |        2 |    1000000 |          0 | 2026-09-08 14:17:21.631365+00
```

### A-5 疑似未使用索引（idx_scan=0）

```text
      indexrelname       | relname |  大小
 orders_pkey             | orders  | 896 kB
 orders_order_no_key     | orders  | 1248 kB
 idx_orders_user_created | orders  | 1248 kB
 idx_orders_created      | orders  | 896 kB
 idx_orders_amount       | orders  | 896 kB
```

> ⚠ `idx_scan=0` ≠ 该删：orders 是 3 行的小表（seq scan 更便宜），且统计只从上次 reset 起算。"看 0 就删索引"是教条。

## B 组 · 统计系统的脾气

### B-1 统计延迟 + `pg_stat_force_next_flush()`

```text
 a_刚插入后立刻查     | n_tup_ins: 0        ← 刚提交的 INSERT 统计里还没有
 b_force_next_flush后 | n_tup_ins: 1000     ← 官方提供的强制落账函数
 c_单表重置后         | n_tup_ins: 0        ← pg_stat_reset_single_table_counters 清零
```

## C 组 · 等待事件

### C-1 三态合影（真实锁等待现场）

```text
  pid  |        state        | wait_event_type |  wait_event   |             query
 29700 | idle in transaction | Client          | ClientRead    | UPDATE finance.replication_dem   ← 持锁但等客户端
 29701 | active              | Lock            | transactionid | UPDATE finance.replication_dem   ← 等行锁
```

### C-2 谁在等谁（`pg_blocking_pids()`，课 13 手法）

```text
 等待pid |    等事件     | 持锁pid |      持锁state
   29701 | transactionid |   29700 | idle in transaction
```

## D 组 · pg_stat_io（PG 16+）

### D-1 `track_io_timing` 会话级可开（superuser SET，无需重启）；backend_type 10 种

### D-2 同一时刻、同一库、两种 context 的命中率对照

```text
   backend_type    | context  | reads  |   hits   | hit_rate
 client backend    | bulkread | 251517 |    39463 |     13.6   ← 大表 seq scan 绕过共享缓冲（环形缓冲）
 autovacuum worker | vacuum   | 125779 |    98506 |     43.9
 background worker | bulkread | 104530 |    17244 |     14.2
 client backend    | normal   |  66418 | 47207240 |     99.9   ← 普通查询几乎全命中
 client backend    | vacuum   |  23150 |    30434 |     56.8
 background worker | normal   |  11338 |    35006 |     75.5
```

> **bulkread 13.6% vs normal 99.9%**——同库同时刻差 86 pct。"命中率低"必须先问 context，bulkread 天生低是设计行为（不污染共享缓冲），不是故障。

## E 组 · 进度条与慢查询取证

### E-1 VACUUM 进度条（800 万行 / 112198 页 / 400 万 dead tuple）

```text
scanning heap | 21124/112198 (19)
scanning heap | 38622/112198 (34)
scanning heap | 57754/112198 (51)
scanning heap | 80720/112198 (72)
scanning heap | 107255/112198 (96)
```

> 小表（130MB）VACUUM 1 秒内完成根本抓不到进度条——进度条是为大表准备的。

### E-2 auto_explain：会话级 LOAD（无需重启）+ 日志证据

```text
2026-09-10 17:11:41.317 UTC [30413] LOG:  duration: 260.126 ms  plan:
	Query Text: SELECT count(*) FROM finance.io_big WHERE bucket = 42;
	Finalize Aggregate  (cost=154906.55..154906.56 rows=1 width=8) (actual time=257.793..260.117 rows=1 loops=1)
	  ->  Gather  (cost=154906.33..154906.54 rows=2 width=8) (actual time=257.671..260.106 rows=3 loops=1)
	        Workers Planned: 2
	        Workers Launched: 2
	        ->  Parallel Seq Scan on io_big  (cost=0.00..153864.67 rows=16667 width=0) (actual time=148.711..247.289 rows=26667 loops=3)
```

同屏对照（分工实证）——同一份日志里 `log_min_duration_statement` 只给语句文本：

```text
2026-09-10 17:09:56.739 UTC [30270] LOG:  duration: 4889.999 ms  statement: VACUUM finance.io_big;
```

意外收获：800 万行 count 自动触发并行查询（Workers Launched: 2），auto_explain 完整记录了并行计划。

### E-3 pg_stat_statements TOP 3（PG 17 IO 列 shared_blk_read_time）

```text
 total_ms  | calls | mean_ms  | rows | blk_read_ms |                     query
 453451.4  |    13 | 34880.88 |   13 |         0.0 | UPDATE finance.accounts SET balance = balance   ← 课 13 锁实验
 129100.0  |    12 | 10758.34 |   12 |         0.0 | SELECT id FROM finance.accounts WHERE id=$1 FO
  22002.1  |     5 |  4400.42 |   5  |         0.0 | UPDATE finance.replication_demo SET note=$1 WH
```

> TOP 1 的 mean 34.9 秒不是 SQL 慢，是**等锁时间被计入执行时间**（课 13 实验痕迹）——pg_stat_statements 排行榜第一不一定是坏 SQL，要先问"慢在哪"。

## F 组 · 从库监控

### F-1 主从延迟仪表盘

```text
 application_name |   state   | sync_state | replay_lsn | replay_lag_s
 walreceiver      | streaming | async      | 1/F3000000 |
```

> async 时 replay_lag 为 NULL（课 15 实测结论），延迟要靠 replay_lsn 差值计算。

### F-2a 表锁冲突 → `confl_lock`

```text
从库会话: BEGIN RR; SELECT count(*) FROM io_big;  →  pg_sleep(40)
主库: DROP TABLE io_big;
30 秒后从库:
ERROR:  canceling statement due to conflict with recovery
DETAIL:  User was holding a relation lock for too long.
计数器: confl_lock = 1        ← 注意不是 confl_snapshot！
```

### F-2b 快照冲突 → `confl_snapshot`（锁矩阵上 ShareUpdateExclusive 与 AccessShare 不冲突）

```text
从库会话: BEGIN RR; SELECT count(*) FROM io_probe;  →  pg_sleep(45)
主库: DELETE FROM io_probe; VACUUM io_probe;        → 从库重放清理撞从库快照
30 秒后从库:
ERROR:  canceling statement due to conflict with recovery
DETAIL:  User query might have needed to see row versions that must be removed.
计数器: confl_snapshot = 1, confl_lock = 1          ← 两列各有第一手标本
```

> 同一种报错文本（conflict with recovery），两种 DETAIL、两种计数器列——**排障时看 DETAIL 分流，别只看第一行**。

## 收尾状态

- `io_big` 已 DROP；`io_probe` 已 DROP；从库落后 **0 bytes**（streaming）
- 从库上的 `pg_stat_database_conflicts`（confl_snapshot=1 / confl_lock=1）**保留**，作为本课的现场标本
- `pg_stat_statements` / `pg_stat_database` 等累计值含历史实验痕迹（deadlocks=4、TOP1 UPDATE 等），正文已逐一归因
