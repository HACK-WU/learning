#!/usr/bin/env bash
# 课 16《监控与性能》实验脚本（PG 17.11 / Docker / macOS arm64）
# 主库：容器 pg17（5433，库 order_service）；从库：pg17-standby（5435，课 15 基线）
# 实验编号：A1~A5（巡检五件套）/ B1~B2（统计系统脾气）/ C1~C2（等待事件）
#           D1~D3（pg_stat_io）/ E1~E3（进度条 + auto_explain + pg_stat_statements）/ F1~F2（从库监控）
# 原始输出见 out_l16_full.md
set -u
export PATH="/usr/local/bin:$PATH"

# ---------- A1 连接与会话构成 ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY 2 DESC;
   SELECT backend_type, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC;"

# ---------- A2 库级累计 + 缓存命中率 ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT datname, xact_commit, xact_rollback, deadlocks, blks_hit, blks_read,
          round(100.0*blks_hit/nullif(blks_hit+blks_read,0), 2) AS 命中率_pct
   FROM pg_stat_database WHERE datname='order_service';"

# ---------- A3 WAL 与 checkpoint（⚠ PG 17 三视图拆分 + 列名全改） ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT wal_records, pg_size_pretty(wal_bytes::numeric) AS wal总量, wal_buffers_full FROM pg_stat_wal;
   SELECT num_timed, num_requested, buffers_written FROM pg_stat_checkpointer;      -- 不是 checkpoints_timed！
   SELECT buffers_clean, maxwritten_clean, buffers_alloc FROM pg_stat_bgwriter;"

# ---------- A4 表级 TOP ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT relname, seq_scan, idx_scan, n_live_tup, n_dead_tup, last_autovacuum
   FROM pg_stat_user_tables WHERE n_live_tup > 100000 ORDER BY seq_scan DESC LIMIT 6;"

# ---------- A5 疑似未使用索引 ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT indexrelname, relname, pg_size_pretty(pg_relation_size(indexrelid)) AS 大小
   FROM pg_stat_user_indexes WHERE idx_scan = 0 AND relname LIKE 'orders%' LIMIT 5;"

# ---------- B1 统计延迟 + force_next_flush ----------
docker exec -i pg17 psql -U postgres -d order_service <<'EOF'
CREATE TABLE IF NOT EXISTS finance.stat_delay(id int);
SELECT pg_stat_reset_single_table_counters('finance.stat_delay'::regclass);
INSERT INTO finance.stat_delay SELECT generate_series(1,1000);
SELECT 'a_刚插入后立刻查' AS 阶段, n_tup_ins FROM pg_stat_user_tables WHERE relname='stat_delay';
SELECT pg_stat_force_next_flush();
SELECT 'b_force_next_flush后' AS 阶段, n_tup_ins FROM pg_stat_user_tables WHERE relname='stat_delay';
SELECT pg_stat_reset_single_table_counters('finance.stat_delay'::regclass);
SELECT 'c_单表重置后' AS 阶段, n_tup_ins FROM pg_stat_user_tables WHERE relname='stat_delay';
DROP TABLE finance.stat_delay;
EOF

# ---------- C1/C2 等待事件：管道保活制造真实等待 ----------
(echo "BEGIN; UPDATE finance.replication_demo SET note='持锁者' WHERE id=1;"; sleep 25) | \
  docker exec -i pg17 psql -U postgres -d order_service >/tmp/s1.log 2>&1 &
(sleep 3; echo "UPDATE finance.replication_demo SET note='等待者' WHERE id=1;"; sleep 20) | \
  docker exec -i pg17 psql -U postgres -d order_service >/tmp/s2.log 2>&1 &
sleep 6
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT pid, state, wait_event_type, wait_event, left(query,30) AS query
   FROM pg_stat_activity
   WHERE datname='order_service' AND backend_type='client backend' AND pid <> pg_backend_pid();"
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT blocked.pid AS 等待pid, blocked.wait_event AS 等事件, blocking.pid AS 持锁pid, blocking.state AS 持锁state
   FROM pg_stat_activity blocked
   JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) b ON true
   JOIN pg_stat_activity blocking ON blocking.pid = b
   WHERE blocked.wait_event_type='Lock';"
wait 2>/dev/null

# ---------- D 组 pg_stat_io（PG 16+） ----------
docker exec pg17 psql -U postgres -d order_service -c "SET track_io_timing = on;"
docker exec pg17 psql -U postgres -d order_service -c \
  "CREATE TABLE finance.io_probe AS SELECT g, md5(g::text::varchar) FROM generate_series(1,2000000) g;"
docker exec pg17 psql -U postgres -d order_service -c "SET track_io_timing=on; SELECT count(*) FROM finance.io_probe;" >/dev/null
docker exec pg17 psql -U postgres -d order_service -c "SELECT pg_stat_force_next_flush();
  SELECT backend_type, context, reads, hits,
         round(100.0*hits/nullif(reads+hits,0),1) AS hit_rate
  FROM pg_stat_io WHERE object='relation' AND reads > 0 ORDER BY reads DESC LIMIT 6;"

# ---------- E1 VACUUM 进度条（800 万行大表才抓得住） ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "CREATE TABLE finance.io_big AS SELECT g AS id, md5(g::text::varchar) AS payload, g % 100 AS bucket
   FROM generate_series(1,8000000) g;
   ALTER TABLE finance.io_big SET (autovacuum_enabled = false);
   UPDATE finance.io_big SET payload = md5(id::text::varchar) WHERE id % 2 = 0;"   # 400 万 dead
(echo "VACUUM finance.io_big;"; sleep 90) | docker exec -i pg17 psql -U postgres -d order_service >/tmp/vac2.log 2>&1 &
sleep 1.2
for i in $(seq 1 12); do
  docker exec pg17 psql -U postgres -d order_service -t -A -c \
    "SELECT phase || ' | ' || heap_blks_scanned || '/' || heap_blks_total || ' (' ||
            coalesce(round(100.0*heap_blks_scanned/nullif(heap_blks_total,0))::text,'%','-') || ')'
     FROM pg_stat_progress_vacuum;"
  sleep 0.8
done
wait 2>/dev/null

# ---------- E2 auto_explain（会话级 LOAD，无需重启） ----------
docker exec -i pg17 psql -U postgres -d order_service <<'EOF'
LOAD 'auto_explain';
SET auto_explain.log_min_duration = 0;
SET auto_explain.log_analyze = on;
SELECT count(*) FROM finance.io_big WHERE bucket = 42;
EOF
docker logs pg17 2>&1 | grep -B 1 -A 7 "plan:" | tail -14   # stderr 进 docker logs

# ---------- E3 pg_stat_statements TOP（PG 17 IO 列 shared_blk_read_time） ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT round(total_exec_time::numeric,1) AS total_ms, calls, round(mean_exec_time::numeric,2) AS mean_ms,
          rows, shared_blk_read_time::numeric(10,1) AS blk_read_ms, left(query,46) AS query
   FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 3;"

# ---------- F1 主从延迟仪表盘 ----------
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT application_name, state, sync_state, replay_lsn,
          round(extract(epoch from replay_lag)::numeric,3) AS replay_lag_s
   FROM pg_stat_replication;"

# ---------- F2a 表锁冲突 → confl_lock ----------
(sleep 1; echo "BEGIN ISOLATION LEVEL REPEATABLE READ;"; echo "SELECT count(*) FROM finance.io_big;"; echo "SELECT pg_sleep(40);"; sleep 45) | \
  docker exec -i pg17-standby psql -U postgres -d order_service >/tmp/sb.log 2>&1 &
sleep 3
( echo "DROP TABLE finance.io_big;"; sleep 3 ) | docker exec -i pg17 psql -U postgres -d order_service >/tmp/pd.log 2>&1
wait 2>/dev/null
tail -4 /tmp/sb.log      # ERROR: canceling statement due to conflict with recovery
                         # DETAIL: User was holding a relation lock for too long.  → confl_lock+1

# ---------- F2b 快照冲突 → confl_snapshot（锁矩阵上不冲突，唯一冲突源是行版本） ----------
docker exec pg17 psql -U postgres -d order_service -c "CREATE TABLE finance.io_probe AS SELECT g, md5(g::text::varchar) FROM generate_series(1,2000000) g;" >/dev/null
(sleep 1; echo "BEGIN ISOLATION LEVEL REPEATABLE READ;"; echo "SELECT count(*) FROM finance.io_probe;"; echo "SELECT pg_sleep(45);"; sleep 50) | \
  docker exec -i pg17-standby psql -U postgres -d order_service >/tmp/sb2.log 2>&1 &
sleep 3
( echo "DELETE FROM finance.io_probe;"; echo "VACUUM finance.io_probe;"; sleep 5 ) | \
  docker exec -i pg17 psql -U postgres -d order_service >/tmp/pd2.log 2>&1
wait 2>/dev/null
tail -4 /tmp/sb2.log     # DETAIL: User query might have needed to see row versions that must be removed. → confl_snapshot+1
docker exec pg17-standby psql -U postgres -d order_service -c \
  "SELECT confl_snapshot, confl_lock FROM pg_stat_database_conflicts WHERE datname='order_service';"

# ---------- 收尾 ----------
docker exec pg17 psql -U postgres -d order_service -c "DROP TABLE IF EXISTS finance.io_probe;"
