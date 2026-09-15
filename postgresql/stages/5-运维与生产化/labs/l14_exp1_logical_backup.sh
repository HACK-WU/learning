#!/usr/bin/env bash
# 课 14 · 实验 1：逻辑备份与恢复（pg_dump / pg_restore / pg_dumpall）
#
# 运行方式（宿主机）：
#   export PATH="/usr/local/bin:$PATH"
#   docker exec -i pg17 bash -s < l14_exp1_logical_backup.sh > out_exp1.txt 2>&1
#
# 环境：容器 pg17（PostgreSQL 17.11，端口 5433），库 order_service（约 661 MB / 24 张表）
# 说明：本脚本不接错误即退（很多步骤要故意观察报错），故不加 set -e

cd /tmp/l14 || { mkdir -p /tmp/l14 && cd /tmp/l14; }

echo "=== A-1: pg_dump 四种格式（体积对比） ==="
pg_dump -U postgres -d order_service -Fp -f a_plain.sql      # plain（默认）
pg_dump -U postgres -d order_service -Fc -f a_custom.dump    # custom
pg_dump -U postgres -d order_service -Fd -j 4 -f a_dir       # directory（唯一支持并行）
pg_dump -U postgres -d order_service -Ft -f a_tar.tar        # tar
echo "--- 体积 ---"
du -sh a_plain.sql a_custom.dump a_dir a_tar.tar
# 实测：plain 158M / custom 45M / directory 45M / tar 158M（tar 不支持压缩）

echo
echo "=== A-2: 格式内部结构 ==="
echo "--- plain 头部（PG 17 会写 \\restrict 随机键） ---"
head -14 a_plain.sql
echo "--- plain 用 COPY 装载数据，共 $(grep -c '^COPY ' a_plain.sql) 条 ---"
grep -n "^COPY " a_plain.sql | head -6
echo "--- custom 是二进制（魔数 PGDMP） ---"
head -c 48 a_custom.dump | od -c | head -4
echo "--- directory 是「一表一文件」的 gz 集合，共 $(ls a_dir | wc -l) 个文件 ---"
ls -la a_dir/ | head -12
echo "--- tar 内含 toc.dat + 各表 .dat ---"
tar -tf a_tar.tar | head -6

echo
echo "=== B-1: pg_restore 读不了 plain 格式（关键区别） ==="
pg_restore -l a_plain.sql
echo "退出码: $?   ← 报错 input file appears to be a text format dump. Please use psql."

echo
echo "=== B-2: -l 列出归档目录（custom 的 TOC） ==="
pg_restore -l a_custom.dump | head -18

echo
echo "=== B-3: 完整恢复到新库（directory + -j 4） ==="
dropdb -U postgres --if-exists b_restored 2>/dev/null
createdb -U postgres -T template0 b_restored          # 从 template0 保证是干净空库
time pg_restore -U postgres -d b_restored -j 4 a_dir
echo "--- 验证 ---"
psql -U postgres -d b_restored -tAc "SELECT 'orders_big='||count(*) FROM finance.orders_big;"
psql -U postgres -d b_restored -tAc "SELECT 'tables='||count(*) FROM pg_tables WHERE schemaname='finance';"
psql -U postgres -d b_restored -tAc "SELECT 'db_size='||pg_size_pretty(pg_database_size('b_restored'));"

echo
echo "=== B-4: 重复恢复同一归档（不加 --clean） ==="
pg_restore -U postgres -d b_restored a_custom.dump 2>&1 | tail -5
echo "--- 报错条数（不加 -e → 跑完整份归档） ---"
pg_restore -U postgres -d b_restored a_custom.dump 2>&1 | grep -c 'error:'   # 实测 113
echo "--- 报错条数（加 -e → 第一个错误就停） ---"
pg_restore -U postgres -d b_restored -e a_custom.dump 2>&1 | grep -c 'error:' # 实测 1
echo "--- 退出码（两种情况都为 1，脚本能捕获） ---"
pg_restore -U postgres -d b_restored a_custom.dump >/dev/null 2>&1; echo "不加 -e: $?"

echo
echo "=== B-5: 加 --clean --if-exists 后重复恢复不报错 ==="
pg_restore -U postgres -d b_restored --clean --if-exists a_custom.dump 2>&1 | tail -3

echo
echo "=== B-6: -t 只恢复一张表（官方警告：不恢复它所依赖的其他对象） ==="
dropdb -U postgres --if-exists b_single 2>/dev/null
createdb -U postgres -T template0 b_single
pg_restore -U postgres -d b_single -n finance -t accounts a_custom.dump 2>&1 | tail -3
# 实测报错：ERROR: schema "finance" does not exist  ← schema 本身没被恢复

echo
echo "=== B-7: --schema-only / --data-only ==="
dropdb -U postgres --if-exists b_schema 2>/dev/null
createdb -U postgres -T template0 b_schema
pg_restore -U postgres -d b_schema -s a_custom.dump 2>&1 | tail -2
psql -U postgres -d b_schema -tAc "SELECT '结构在、数据空: '||count(*) FROM finance.accounts;"  # 0
pg_restore -U postgres -d b_schema -a a_custom.dump 2>&1 | tail -2
psql -U postgres -d b_schema -tAc "SELECT '补数据后: '||count(*) FROM finance.accounts;"        # 3

echo
echo "=== C: pg_dumpall 补上 pg_dump 不含的全局对象 ==="
pg_dumpall -U postgres --globals-only 2>&1 | head -16
echo "a_plain.sql 中 CREATE ROLE 次数: $(grep -c 'CREATE ROLE' a_plain.sql || echo 0)"        # 0
echo "globals 中 CREATE ROLE 次数: $(pg_dumpall -U postgres --globals-only 2>/dev/null | grep -c 'CREATE ROLE' || echo 0)"  # 1
