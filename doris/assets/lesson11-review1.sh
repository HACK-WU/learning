#!/bin/bash
# 课 11 评审 1（learner 视角）：正文里出现的每条 SQL 语句，逐条实跑看能不能跑通
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
L=/mnt/d/projects/learning/doris/stages/4-分布式运维与生产落地/lessons/lesson-11-日常运维SchemaChange备份与升级.md

echo "########## learner 视角评审：正文 SQL 语句逐条实跑 ##########"

echo ""
echo "===== 1. 第一幕的两张建表语句（正文原样）====="
q "DROP TABLE IF EXISTS rv_light;" >/dev/null 2>&1
q "DROP TABLE IF EXISTS rv_heavy;" >/dev/null 2>&1
echo "--- sc_light 建表（正文写法）---"
q "CREATE TABLE rv_light (
    id      INT,
    dt      DATE,
    amount  DECIMAL(10,2)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 4
PROPERTIES ('replication_num' = '1', 'light_schema_change' = 'true');"
echo "--- sc_heavy 建表（正文写法）---"
q "CREATE TABLE rv_heavy (
    id      INT,
    dt      DATE,
    amount  DECIMAL(10,2)
)
DUPLICATE KEY(id)
DISTRIBUTED BY HASH(id) BUCKETS 4
PROPERTIES ('replication_num' = '1', 'light_schema_change' = 'false');"
echo "--- 确认属性 ---"
q "SHOW CREATE TABLE rv_light\G" | grep -iE "light_schema_change"
q "SHOW CREATE TABLE rv_heavy\G" | grep -iE "light_schema_change"

echo ""
echo "===== 2. 第二幕的加列与查询（正文原样）====="
q "INSERT INTO rv_light SELECT number, DATE_ADD('2026-01-01', INTERVAL (number % 365) DAY), number*1.5 FROM numbers('number'='100000');"
q "INSERT INTO rv_heavy SELECT number, DATE_ADD('2026-01-01', INTERVAL (number % 365) DAY), number*1.5 FROM numbers('number'='100000');"
sleep 3
echo "--- light 加列 + 立刻查 ---"
q "ALTER TABLE rv_light ADD COLUMN remark VARCHAR(100) DEFAULT 'light-ok';"
q "SELECT id, dt, amount, remark FROM rv_light WHERE id = 1;"
echo "--- heavy 加列 + 立刻查（应报错）---"
q "ALTER TABLE rv_heavy ADD COLUMN remark VARCHAR(100) DEFAULT 'heavy-ok';"
q "SELECT id, dt, amount, remark FROM rv_heavy WHERE id = 1;"
echo "--- 等 FINISHED 后再查 ---"
sleep 3
q "SELECT id, dt, amount, remark FROM rv_heavy WHERE id = 1;"

echo ""
echo "===== 3. 知识点 1 支持矩阵：正文列的每条语句 ====="
declare -a SQLS=(
  "ALTER TABLE rv_light ADD COLUMN c1 INT DEFAULT '1';"
  "ALTER TABLE rv_light ADD COLUMN c2 INT DEFAULT '2' AFTER amount;"
  "ALTER TABLE rv_light DROP COLUMN c1;"
  "ALTER TABLE rv_light RENAME COLUMN c2 renamed_c2;"
  "ALTER TABLE rv_light MODIFY COLUMN renamed_c2 BIGINT;"
)
for s in "${SQLS[@]}"; do
  OUT=$(q "$s" 2>&1)
  if [ -z "$OUT" ]; then echo "  [OK]   $s"; else echo "  [ERR]  $s => $OUT"; fi
done

echo ""
echo "===== 4. 正文里 VARCHAR 加长（50->200）====="
q "DROP TABLE IF EXISTS rv_len;" >/dev/null 2>&1
q "CREATE TABLE rv_len (id INT, k VARCHAR(50)) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num'='1');"
q "INSERT INTO rv_len SELECT number, CONCAT('k', number) FROM numbers('number'='50000');"
sleep 2
q "ALTER TABLE rv_len MODIFY COLUMN k VARCHAR(200);" 2>&1 | sed 's/^/  /'
sleep 2
q "DESC rv_len;" | grep -E "^k" | sed 's/^/  /'

echo ""
echo "===== 5. 正文提到的 RENAME COLUMN（写法是否真能用）====="
q "ALTER TABLE rv_len RENAME COLUMN k newk;" 2>&1 | sed 's/^/  /'
q "DESC rv_len;" | sed 's/^/  /'

echo ""
echo "===== 6. 正文支持矩阵里的每条被拒语句（确认报错与正文一致）====="
echo "--- 6a VARCHAR 缩短 ---"
q "ALTER TABLE rv_len MODIFY COLUMN newk VARCHAR(20);" 2>&1 | grep -oE "Shorten type length is prohibited[^\\\\]*" | head -1 | sed 's/^/  /'
echo "--- 6b 跨类型收窄 ---"
q "ALTER TABLE rv_len MODIFY COLUMN id VARCHAR(10);" 2>&1 | grep -oE "Can not change from wider type[^\\\\]*" | head -1 | sed 's/^/  /'
echo "--- 6c ORDER BY 写漏列 ---"
q "ALTER TABLE rv_light ORDER BY (dt, id);" 2>&1 | grep -oE "Reorder stmt should contains all columns" | head -1 | sed 's/^/  /'
echo "--- 6d 无分区表改分桶 ---"
q "ALTER TABLE rv_light MODIFY DISTRIBUTION DISTRIBUTED BY HASH(id) BUCKETS 8;" 2>&1 | grep -oE "Only support change partitioned table[^\\\\]*" | head -1 | sed 's/^/  /'

echo ""
echo "===== 7. 正文仓库建语句（4 个属性名是否都有效）====="
q "DROP REPOSITORY rv_repo;" 2>&1 | grep -oE "Repository does not exist" | sed 's/^/  (预期) /'
q "CREATE REPOSITORY rv_repo
WITH S3
ON LOCATION 's3://doris-demo/backup_rv'
PROPERTIES (
    's3.endpoint'     = 'http://minio:9000',
    's3.access_key'   = 'minioadmin',
    's3.secret_key'   = 'minioadmin',
    's3.region'       = 'us-east-1',
    'use_path_style'  = 'true'
);" 2>&1 | sed 's/^/  /'
q "SHOW REPOSITORIES;" | sed 's/^/  /'

echo ""
echo "===== 8. 正文的 RESTORE 语句（带 replication_num）====="
q "DROP TABLE IF EXISTS rv_bak;" >/dev/null 2>&1
q "CREATE TABLE rv_bak (id INT, v INT) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num'='1');"
q "INSERT INTO rv_bak SELECT number, number FROM numbers('number'='50000');"
sleep 3
q "BACKUP SNAPSHOT shop.rv_v1 TO rv_repo ON (rv_bak);" 2>&1 | sed 's/^/  /'
for i in $(seq 1 40); do
  ST=$(q "SHOW BACKUP\G" | grep -E "^ +State:" | awk '{print $2}' | tail -1)
  [ "$ST" = "FINISHED" ] && break
  [ "$ST" = "CANCELLED" ] && break
  sleep 1
done
echo "  备份 State=$ST"
TS=$(q "SHOW SNAPSHOT ON rv_repo WHERE SNAPSHOT='rv_v1';" | awk -F'\t' 'NR==2{print $2}')
echo "  TS=$TS"
q "DROP TABLE IF EXISTS rv_bak_r;" >/dev/null 2>&1
q "RESTORE SNAPSHOT shop.rv_v1 FROM rv_repo ON (rv_bak AS rv_bak_r)
   PROPERTIES ('backup_timestamp' = '$TS', 'replication_num' = '1');" 2>&1 | sed 's/^/  /'
for i in $(seq 1 40); do
  ST=$(q "SHOW RESTORE\G" | grep -E "^ +State:" | awk '{print $2}' | tail -1)
  [ "$ST" = "FINISHED" ] && break
  [ "$ST" = "CANCELLED" ] && break
  sleep 1
done
echo "  恢复 State=$ST"
q "SELECT COUNT(*) c, SUM(v) s FROM rv_bak_r;" 2>&1 | sed 's/^/  /'
q "SELECT COUNT(*) c, SUM(v) s FROM rv_bak;" 2>&1 | sed 's/^/  源表 /'

echo ""
echo "===== 9. 正文速览里的 SHOW PROC 命令 ====="
q "SHOW PROC '/statistic';" | sed 's/^/  /'
q "SHOW PROC '/cluster_health/tablet_health';" | cut -f1-6 | sed 's/^/  /'
q "SHOW BACKENDS\G" | grep -E "UsedPct|Alive" | sed 's/^/  /'
q "SHOW FRONTENDS\G" | grep -E "Version|Alive" | sed 's/^/  /'

echo ""
echo "===== 10. 正文里 CANCEL 语法（确认报的是正文写的那个错）====="
q "CANCEL ALTER TABLE COLUMN FROM shop.rv_light;" 2>&1 | grep -oE "not under SCHEMA_CHANGE" | sed 's/^/  /'
echo "--- 以及 WHERE JobId 写法 ---"
q "CANCEL ALTER TABLE COLUMN FROM shop WHERE JobId = 123;" 2>&1 | grep -oE "mismatched input 'WHERE'[^\\\\]*" | head -1 | sed 's/^/  /'

echo ""
echo "===== 11. 清理评审表 ====="
for t in rv_light rv_heavy rv_len rv_bak rv_bak_r; do
  q "DROP TABLE IF EXISTS $t;" >/dev/null 2>&1
done
q "DROP REPOSITORY rv_repo;" 2>&1 | head -1 | sed 's/^/  /'
echo "  清理完成"
