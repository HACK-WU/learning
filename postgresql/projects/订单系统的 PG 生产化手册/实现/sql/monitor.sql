-- PG 17 巡检五件套：连接、复制、WAL/checkpoint、表与语句、等待事件。
\x on
\echo '=== 1. 连接与等待 ==='
SELECT pid, usename, state, wait_event_type, wait_event,
       clock_timestamp() - query_start AS query_age,
       left(query, 120) AS query
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY query_start NULLS LAST;

\echo '=== 2. 复制延迟与槽 ==='
SELECT application_name, state, sync_state,
       write_lag, flush_lag, replay_lag,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_gap
FROM pg_stat_replication;
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;

\echo '=== 3. WAL 与 checkpoint（PG 17 视图） ==='
SELECT num_timed, num_requested, restartpoints_timed, restartpoints_req,
       restartpoints_done, buffers_written, stats_reset
FROM pg_stat_checkpointer;
SELECT wal_records, wal_fpi, pg_size_pretty(wal_bytes) AS wal_bytes,
       wal_buffers_full, wal_write, wal_sync, stats_reset
FROM pg_stat_wal;

\echo '=== 4. 表级写入与清理 ==='
SELECT relname, n_live_tup, n_dead_tup, n_tup_ins, n_tup_upd, n_tup_del,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC NULLS LAST
LIMIT 10;

\echo '=== 5. 数据库级命中率与语句 ==='
SELECT datname, blks_hit, blks_read,
       round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       xact_commit, xact_rollback, temp_files, temp_bytes
FROM pg_stat_database
WHERE datname = current_database();
SELECT calls, round(total_exec_time::numeric, 2) AS total_ms,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows, shared_blks_hit, shared_blks_read,
       left(query, 140) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
