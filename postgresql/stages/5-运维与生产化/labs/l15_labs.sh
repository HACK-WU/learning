#!/usr/bin/env bash
# 课 15《复制与高可用》实验脚本（PG 17.11 / Docker / macOS arm64）
# 主库：容器 pg17（端口 5433，库 order_service）
# 从库：容器 pg17-standby（端口 5435，volume pg17-standby-data）
# 级联从库：容器 pg17-standby2（端口 5436，实验 D-1 后已删除）
#
# 实验编号与正文对应：A1~A5（从库搭建）/ B1~B4（同步复制）/ C1~C4（复制槽）/ D1~D3（切换与分叉）
# 原始输出见 out_l15_full.md
set -u  # 不用 set -e：挂起实验（B3）依赖 timeout 兜底
export PATH="/usr/local/bin:$PATH"

H="host.docker.internal"   # 容器访问宿主端口映射的统一入口（本机容器间网桥直连报 EADDRNOTAVAIL，见正文误区 6）

# ---------- 0. 环境准备 ----------
# docker network create pgnet
# docker network connect pgnet pg17
# docker run -d --name pg17-standby --network pgnet --memory 1g -p 5435:5432 \
#   -v pg17-standby-data:/var/lib/postgresql/data postgres:17 sleep infinity

# ---------- A1 主库三件套 ----------
# 主库侧默认值开箱即满足：wal_level=replica / max_wal_senders=10 / max_replication_slots=10
docker exec pg17 psql -U postgres -t -c "SHOW wal_level; SHOW max_wal_senders; SHOW max_replication_slots;"
# 复制用户（pg_hba 需另放行，见误区 6）
docker exec pg17 psql -U postgres -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica15';"
docker exec pg17 bash -c "echo 'host replication replicator 169.254.169.254/32 scram-sha-256' >> /var/lib/postgresql/data/pg_hba.conf"
docker exec pg17 psql -U postgres -c "SELECT pg_reload_conf();"

# ---------- A2 一条 basebackup 变一台从库（课 14 三块积木） ----------
docker exec pg17 psql -U postgres -c "CHECKPOINT;"
docker exec -u postgres -e PGPASSWORD=replica15 pg17-standby \
  pg_basebackup -h $H -p 5433 -U replicator -D /var/lib/postgresql/data \
  -Fp -X stream -R -P --checkpoint=fast        # -R 自动写 standby.signal + primary_conninfo
# 起从库
docker exec -u postgres -d pg17-standby postgres -D /var/lib/postgresql/data

# ---------- A3/A4/A5 复制建立验证 ----------
docker exec pg17-standby psql -U postgres -t -c "SELECT pg_is_in_recovery(), pg_last_wal_replay_lsn();"
docker exec pg17 psql -U postgres -d order_service -c \
  "SELECT pid, usename, application_name, client_addr, state, sync_state, sent_lsn, replay_lsn FROM pg_stat_replication;"
docker exec pg17 psql -U postgres -d order_service -c \
  "INSERT INTO finance.replication_demo VALUES (1,'主库刚写的订单');"
docker exec pg17-standby psql -U postgres -d order_service -t -c "SELECT id, note FROM finance.replication_demo;"
docker exec pg17-standby psql -U postgres -c \
  "SELECT pid, status, sender_host, sender_port, slot_name, written_lsn, latest_end_lsn FROM pg_stat_wal_receiver;"

# ---------- B1 application_name（同步复制按名字匹配） ----------
# primary_conninfo 里追加 application_name=standby1 后 pg_reload_conf()
docker exec pg17 psql -U postgres -d order_service -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"

# ---------- B2 同步复制四档延迟 ----------
# 注意：synchronous_standby_names 不能 session SET（实测报 cannot be changed now），必须 ALTER SYSTEM + reload
docker exec pg17 psql -U postgres -c "ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (standby1)';"
docker exec pg17 psql -U postgres -c "SELECT pg_reload_conf();"
docker exec -i pg17 psql -U postgres -d order_service <<'SQL'
\timing on
SET synchronous_commit = 'local';
INSERT INTO finance.replication_demo VALUES (202,'local');
SET synchronous_commit = 'on';
INSERT INTO finance.replication_demo VALUES (203,'on');
SET synchronous_commit = 'remote_write';
INSERT INTO finance.replication_demo VALUES (204,'remote_write');
SET synchronous_commit = 'remote_apply';
INSERT INTO finance.replication_demo VALUES (205,'remote_apply');
SELECT application_name, sync_state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;
SQL

# ---------- B3 从库没了，同步提交挂起（本课最贵实验） ----------
docker exec -u postgres pg17-standby pg_ctl stop -D /var/lib/postgresql/data -m fast
time timeout 6 docker exec pg17 psql -U postgres -d order_service \
  -c "INSERT INTO finance.replication_demo VALUES (301,'这条提交在等一个不存在的从库');"
# 客户端被杀 ≠ 事务回滚：in-doubt 事务等从库回来后最终提交（B4 复插 301 报 duplicate key 实证）
docker exec pg17 psql -U postgres -d order_service -t -c "SELECT count(*) FROM finance.replication_demo WHERE id=301;"   # 当时 = 0
time timeout 4 docker exec pg17 psql -U postgres -d order_service \
  -c "UPDATE finance.replication_demo SET note='任何同步会话都卡' WHERE id=1;"   # 其他会话也卡（全局挂起）
# 恢复：从库一回来，挂起解除
docker exec -u postgres -d pg17-standby postgres -D /var/lib/postgresql/data
docker exec pg17 psql -U postgres -d order_service -c "INSERT INTO finance.replication_demo VALUES (301,'X');"   # → duplicate key!
docker exec pg17 psql -U postgres -c "ALTER SYSTEM RESET synchronous_standby_names;"   # 清理

# ---------- C1/C2 无槽的代价：WAL 被回收，从库追不上 ----------
docker exec pg17 psql -U postgres -d order_service -t -c "SHOW wal_keep_size; SELECT count(*) FROM pg_replication_slots;"
docker exec -u postgres pg17-standby pg_ctl stop -D /var/lib/postgresql/data -m fast
docker exec pg17 psql -U postgres -d order_service -c \
  "CREATE TABLE finance.wal_filler AS SELECT g, md5(g::text::varchar) FROM generate_series(1,2000000) g;"   # ~200MB WAL
docker exec pg17 psql -U postgres -c "CHECKPOINT;"
docker exec pg17 psql -U postgres -d order_service -t -c "SELECT count(*) || ' 段 / ' || pg_size_pretty(sum(size)) FROM pg_ls_waldir();"
# checkpoint 日志会出现 "14 removed, 0 recycled"
docker exec -u postgres -d pg17-standby postgres -D /var/lib/postgresql/data
docker logs pg17 2>&1 | grep -i "already been removed"     # → ERROR: requested WAL segment 000000010000000100000021 has already been removed
# 修复 = 重新 basebackup（无槽丢 WAL 的唯一出路）

# ---------- C3 有槽的对照：WAL 被钉住 ----------
docker exec pg17 psql -U postgres -c "SELECT * FROM pg_create_physical_replication_slot('l15_slot');"
# 重建从库时挂槽（--slot 会把 primary_slot_name 写进 auto.conf）
docker exec -u postgres -e PGPASSWORD=replica15 pg17-standby \
  pg_basebackup -h $H -p 5433 -U replicator -D /var/lib/postgresql/data -Fp -X stream -R -P --slot=l15_slot --checkpoint=fast
docker exec pg17 psql -U postgres -d order_service -c "SELECT slot_name, slot_type, active, restart_lsn, wal_status FROM pg_replication_slots;"
# 停从库 → 写 WAL → checkpoint：段数不变（restart_lsn 钉住）
docker exec -u postgres pg17-standby pg_ctl stop -D /var/lib/postgresql/data -m fast
docker exec pg17 psql -U postgres -d order_service -c "INSERT INTO finance.wal_filler SELECT g+2000000, md5(g::text::varchar) FROM generate_series(1,2000000) g;"
docker exec pg17 psql -U postgres -c "CHECKPOINT;"
docker exec pg17 psql -U postgres -d order_service -t -c \
  "SELECT count(*) || ' 段 / ' || pg_size_pretty(sum(size)) FROM pg_ls_waldir(); SELECT restart_lsn, wal_status FROM pg_replication_slots;"

# ---------- C4 级联复制 ----------
# standby2：从 standby(5435) 再 basebackup（standby 此刻 = 接收器 + 发送器）
docker exec -u postgres -e PGPASSWORD=replica15 pg17-standby2 \
  pg_basebackup -h $H -p 5435 -U replicator -D /var/lib/postgresql/data -Fp -X stream -R -P --checkpoint=fast
# ⚠️ standby2 会继承上游 auto.conf 里的 primary_slot_name='l15_slot'（槽在主库不在 standby）→ walcarrier 反复失败
# 修复：删除 standby2 的 primary_slot_name 行 + 删除继承的第一行 primary_conninfo（port=5433）→ pg_reload_conf()
docker exec pg17 psql -U postgres -d order_service -t -c "SELECT '主库只见直接下游:', count(*) FROM pg_stat_replication;"        # = 1
docker exec pg17-standby psql -U postgres -d order_service -t -c "SELECT 'standby下游:', count(*) FROM pg_stat_replication;"    # = 1
docker exec pg17-standby2 psql -U postgres -c "SELECT sender_host, sender_port, status FROM pg_stat_wal_receiver;"              # → 5435
docker exec pg17 psql -U postgres -d order_service -c "INSERT INTO finance.replication_demo VALUES (401,'经级联到达第三台');"
docker exec pg17-standby2 psql -U postgres -d order_service -t -c "SELECT id FROM finance.replication_demo WHERE id=401;"       # 立即可见

# ---------- D1 promote（从库升主） ----------
docker exec pg17-standby psql -U postgres -d order_service -c "SELECT pg_promote(wait := true, wait_seconds := 30);"
docker exec pg17-standby psql -U postgres -d order_service -t -c "SELECT pg_is_in_recovery(), pg_current_wal_lsn();"
docker exec pg17-standby bash -c "ls /var/lib/postgresql/data/standby.signal"        # → No such file（自动删除）
docker exec pg17 psql -U postgres -d order_service -t -c "SELECT timeline_id FROM pg_control_checkpoint();"          # 旧主 = 1
docker exec pg17-standby psql -U postgres -d order_service -t -c "SELECT timeline_id FROM pg_control_checkpoint();"  # 新主 = 2
docker exec pg17 psql -U postgres -d order_service -c "SELECT slot_name, active FROM pg_replication_slots;"          # 槽 inactive

# ---------- D2/D3 级联跟随与脑裂分叉 ----------
docker exec pg17-standby2 psql -U postgres -c "SELECT sender_port, status FROM pg_stat_wal_receiver;"   # 仍连 5435（新 timeline 自动跟随）
docker exec pg17 psql -U postgres -d order_service -c "INSERT INTO finance.replication_demo VALUES (501,'旧主5433上写入的行');"
docker exec pg17-standby psql -U postgres -d order_service -t -c "SELECT count(*) FROM finance.replication_demo WHERE id=501;"   # = 0（分叉！）
docker exec pg17-standby psql -U postgres -d order_service -c "INSERT INTO finance.replication_demo VALUES (502,'新主5435上写入的行');"
docker exec pg17 psql -U postgres -d order_service -t -c "SELECT count(*) FROM finance.replication_demo WHERE id=502;"           # = 0（分叉！）
# 修复分叉需 pg_rewind（纸面讲解，见 15.3）——实验后环境复位：删 standby2、重建 standby 为从库
