#!/usr/bin/env bash
# 课 14 · 实验 3：PITR 完整演练（"误删表 → 恢复到删除前那一刻"）
#
# 对应正文 14.3。这是本课的重头戏，全程在容器 pg17 内进行。
# 运行方式：
#   docker exec -i pg17 bash -s < l14_exp3_pitr.sh > out_exp3.txt 2>&1
#
# 前置：archive_mode = on 且 archive_command 已配置（见 l14_exp2_physical_backup.sh D-6，
#       且已 docker restart pg17；本实验假设归档目录 /var/lib/postgresql/archive 已有 WAL）
#
# 演练设计：
#   T0  拍基础备份
#   T1  写入 3 行「事故前」数据 ← 这就是我们要回去的时刻
#   T2  再写 1 行「事故后」数据（用于验证它不会被恢复回来）
#   T3  DROP TABLE（灾难）
#   然后：把备份复制成新数据目录 → 配 restore_command + recovery_target_time → 起在 5434 端口

cd /var/lib/postgresql

echo "=== E-1: 拍基础备份（plain 格式，产物直接就是数据目录） ==="
rm -rf l14_backup restore
time pg_basebackup -U postgres -D l14_backup -Fp -X stream -c fast
du -sh l14_backup        # 2.1G

echo
echo "=== E-2: 写入 3 行「事故前」数据 ==="
psql -U postgres -d order_service <<'SQL'
DROP TABLE IF EXISTS finance.pitr_demo;
CREATE TABLE finance.pitr_demo (id int PRIMARY KEY, note text, created timestamptz DEFAULT clock_timestamp());
INSERT INTO finance.pitr_demo (id, note) VALUES (1,'事故前-A'),(2,'事故前-B'),(3,'事故前-C');
SQL
psql -U postgres -d order_service -c "SELECT * FROM finance.pitr_demo ORDER BY id;"

echo
echo "=== E-3: 记录恢复目标 T1 + 建命名恢复点 ==="
psql -U postgres -tAc "SELECT clock_timestamp()" > /tmp/T1.txt
cat /tmp/T1.txt | sed 's/^/T1 = /'
psql -U postgres -c "SELECT pg_create_restore_point('before_accident');"
sleep 2

echo
echo "=== E-4: 写入第 4 行（事故后数据，不该被恢复回来） ==="
psql -U postgres -d order_service -c "INSERT INTO finance.pitr_demo (id, note) VALUES (4,'事故后-不该被恢复');"
sleep 2

echo
echo "=== E-5: 灾难 —— 误删表 ==="
psql -U postgres -d order_service -c "DROP TABLE finance.pitr_demo;"
psql -U postgres -d order_service -c "SELECT * FROM finance.pitr_demo;"   # ERROR: does not exist

echo
echo "=== E-6: 强制切换 WAL，确保最后的事务已归档 ==="
psql -U postgres -c "SELECT pg_switch_wal();"
sleep 3
psql -U postgres -c "SELECT archived_count, failed_count FROM pg_stat_archiver;"

echo
echo "=== E-7: 恢复 —— 把备份复制成新数据目录（备份原件不动） ==="
T1=$(sed 's/[[:space:]]*$//' /tmp/T1.txt)
rm -rf restore
cp -a l14_backup restore
chown -R postgres:postgres restore
echo "备份自带的 pg_wal（恢复起点，必须保留，不要清空）:"
ls restore/pg_wal/ | head -3

echo
echo "=== E-8: 写恢复配置 + 建 recovery.signal ==="
cat >> restore/postgresql.auto.conf <<EOF

# ===== PITR 恢复配置 =====
restore_command = 'cp /var/lib/postgresql/archive/%f %p'
recovery_target_time = '$T1'
recovery_target_action = 'promote'
port = 5434
archive_mode = off
EOF
touch restore/recovery.signal
chown postgres:postgres restore/postgresql.auto.conf restore/recovery.signal

echo
echo "=== E-9: 启动恢复实例（端口 5434，原实例照常跑在 5432） ==="
su postgres -c "pg_ctl -D /var/lib/postgresql/restore -l /tmp/restore.log -w -t 120 start"

echo
echo "=== E-10: 验证恢复结果 ==="
psql -p 5434 -U postgres -d order_service -c "SELECT * FROM finance.pitr_demo ORDER BY id;"
psql -p 5434 -U postgres -d order_service -tAc "SELECT count(*) FROM finance.pitr_demo;"          # 3
psql -p 5434 -U postgres -d order_service -tAc "SELECT count(*) FROM finance.pitr_demo WHERE id=4;"  # 0
echo "--- recovery.signal 是否已被自动删除 ---"
ls restore/recovery.signal 2>&1            # No such file or directory
echo "--- timeline（恢复会新建一条时间线） ---"
psql -U postgres -tAc "SELECT timeline_id FROM pg_control_checkpoint();"        # 1（主库）
psql -p 5434 -U postgres -tAc "SELECT timeline_id FROM pg_control_checkpoint();" # 2（恢复实例）

echo
echo "=== E-11: 服务端日志里的恢复全过程（最有价值的一段证据） ==="
grep -aE "recovery|redo|consistent|promot|selected new timeline" /tmp/restore.log | tail -14
# starting point-in-time recovery to ...
# consistent recovery state reached at ...
# recovery stopping before commit of transaction 2507, time ...   ← 精确停在第 4 行事务提交前
# selected new timeline ID: 2
# archive recovery complete

echo
echo "=== E-12（反面对照）: 恢复目标设错会怎样？ ==="
# 把 recovery_target_time 设成一个早于基础备份结束的时间（2020-01-01）
rm -rf restore2
cp -a l14_backup restore2
chown -R postgres:postgres restore2
cat >> restore2/postgresql.auto.conf <<EOF

restore_command = 'cp /var/lib/postgresql/archive/%f %p'
recovery_target_time = '2020-01-01 00:00:00+00'
port = 5435
archive_mode = off
EOF
touch restore2/recovery.signal
chown postgres:postgres restore2/postgresql.auto.conf restore2/recovery.signal
su postgres -c "pg_ctl -D /var/lib/postgresql/restore2 -l /tmp/restore2.log -w -t 60 start"
echo "--- 它「没有报错」，而是静默停在了最早可达点，并 pause ---"
grep -aE "stopping before|pausing" /tmp/restore2.log
psql -p 5435 -U postgres -tAc "SELECT pg_is_in_recovery();"          # true
psql -p 5435 -U postgres -tAc "SHOW recovery_target_action;"          # pause（默认值）
psql -p 5435 -U postgres -d order_service -tAc "SELECT count(*) FROM finance.pitr_demo;"  # 表根本不存在

echo
echo "=== 收尾：停掉演练实例并清理（保留 l14_backup 供课 15 复制课复用） ==="
su postgres -c "pg_ctl -D /var/lib/postgresql/restore stop -m fast"
su postgres -c "pg_ctl -D /var/lib/postgresql/restore2 stop -m fast"
rm -rf /var/lib/postgresql/restore /var/lib/postgresql/restore2
