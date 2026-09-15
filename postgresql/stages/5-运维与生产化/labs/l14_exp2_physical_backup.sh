#!/usr/bin/env bash
# 课 14 · 实验 2：物理备份（pg_basebackup + pg_verifybackup）
#
# 运行方式（宿主机）：
#   docker exec -i pg17 bash -s < l14_exp2_physical_backup.sh > out_exp2.txt 2>&1
#
# 前置：pg_hba.conf 允许本地 replication 连接（官方镜像默认 local replication all trust）
# 注意：--target=client 时备份写到 pg_basebackup 所在机器；本文在容器内跑即写到容器

echo "=== D-1: 全量物理备份（tar + gzip，WAL 走流式 -X stream） ==="
rm -rf /var/lib/postgresql/backup && mkdir -p /var/lib/postgresql/backup
chown postgres:postgres /var/lib/postgresql/backup
psql -U postgres -c "CHECKPOINT;"     # 先清脏页，避免 backup start 等太久
time timeout 180 pg_basebackup -U postgres -D /var/lib/postgresql/backup/base -Ft -z -P
# 实测：数据目录 2.0 GB，耗时约 41.5 s，产物 447 MB
echo "--- 备份产物 ---"
ls -la /var/lib/postgresql/backup/base/
# base.tar.gz 447M / pg_wal.tar.gz 17K / backup_manifest 381K
echo "源数据目录大小: $(du -sh /var/lib/postgresql/data | cut -f1)"   # 3.0G

echo
echo "=== D-2: 体积对照（逻辑 vs 物理，约 10 倍差距） ==="
echo "逻辑 plain   : 158M"
echo "逻辑 custom  : 45M"
echo "物理 tar.gz  : 447M"
echo "源数据目录   : 3.0G"

echo
echo "=== D-3: tar 格式的备份「不能」直接 verifybackup（需先解包） ==="
/usr/lib/postgresql/17/bin/pg_verifybackup /var/lib/postgresql/backup/base 2>&1 | tail -5
# 实测报错：is present in the manifest but not on disk / could not open directory .../pg_wal

echo
echo "=== D-4: 解包后再校验 ==="
mkdir -p /var/lib/postgresql/backup/unpacked
tar -xzf /var/lib/postgresql/backup/base/base.tar.gz -C /var/lib/postgresql/backup/unpacked
mkdir -p /var/lib/postgresql/backup/unpacked/pg_wal
tar -xzf /var/lib/postgresql/backup/base/pg_wal.tar.gz -C /var/lib/postgresql/backup/unpacked/pg_wal
cp /var/lib/postgresql/backup/base/backup_manifest /var/lib/postgresql/backup/unpacked/
/usr/lib/postgresql/17/bin/pg_verifybackup /var/lib/postgresql/backup/unpacked
# 实测：backup successfully verified

echo
echo "=== D-5: 备份清单与 backup_label ==="
head -c 300 /var/lib/postgresql/backup/base/backup_manifest
echo ""
echo "manifest 中文件条数: $(grep -o '\"Path\"' /var/lib/postgresql/backup/base/backup_manifest | wc -l)"  # 2633
echo "--- backup_label（备份的起止 LSN，PITR 的起点） ---"
cat /var/lib/postgresql/backup/unpacked/backup_label
# START WAL LOCATION / CHECKPOINT LOCATION / BACKUP METHOD: streamed / START TIMELINE: 1

echo
echo "=== D-6: 开启 WAL 归档（archive_mode 是 server start 级参数，必须重启） ==="
mkdir -p /var/lib/postgresql/archive && chown postgres:postgres /var/lib/postgresql/archive
psql -U postgres -c "ALTER SYSTEM SET archive_mode = 'on';"
psql -U postgres -c "ALTER SYSTEM SET archive_command = 'test ! -f /var/lib/postgresql/archive/%f && cp %p /var/lib/postgresql/archive/%f';"
psql -U postgres -c "ALTER SYSTEM SET archive_timeout = '60s';"
psql -U postgres -tAc "SHOW archive_mode;"     # 仍是 off → 需要重启
# 宿主机执行：docker restart pg17
# 重启后验证：
psql -U postgres -c "SELECT archived_count, failed_count FROM pg_stat_archiver;"
psql -U postgres -c "SELECT pg_switch_wal();"  # 强制切一个 WAL，观察它被归档
ls -la /var/lib/postgresql/archive/
