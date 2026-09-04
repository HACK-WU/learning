#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "############ 用 SHOW TABLET ... 看真实版本 ############"
echo "--- 先建一张单桶表，做 50 次单行 INSERT ---"
Q "DROP TABLE IF EXISTS vt"
Q "CREATE TABLE vt (id BIGINT, val VARCHAR(32)) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1 PROPERTIES ('replication_num'='1')"

for i in $(seq 1 50); do
  Q "INSERT INTO vt VALUES ($i,'x$i')" > /dev/null 2>&1
done
echo "50 次单行 INSERT 完成"

TID=$(Q "SHOW TABLETS FROM vt" | awk -F'\t' 'NR>1{print $1; exit}')
echo "TabletId: $TID"

echo ""
echo "--- SHOW TABLET 详情 ---"
Q "SHOW TABLET $TID\G" | grep -iE "Version|RowCount|State|Compaction"

echo ""
echo "--- 用 BE 的 compaction status API ---"
Q "SHOW TABLET $TID" | head -2

echo ""
echo "############ 对照：单次批量 INSERT 50 行 ############"
Q "TRUNCATE TABLE vt"
VALS=""
for i in $(seq 1 50); do
  if [ -n "$VALS" ]; then VALS="$VALS,"; fi
  VALS="$VALS($i,'x$i')"
done
Q "INSERT INTO vt VALUES $VALS"
TID2=$(Q "SHOW TABLETS FROM vt" | awk -F'\t' 'NR>1{print $1; exit}')
echo "批量后 TabletId: $TID2"
Q "SHOW TABLET $TID2\G" | grep -iE "Version|RowCount|State"

echo ""
echo "############ 直接打 BE 的 tablet meta API（拿真实版本数）############"
docker exec doris-learn curl -s "http://127.0.0.1:8040/api/meta/header/$TID2" 2>&1 | head -30

echo ""
echo "############ 用 information_schema 查版本 ############"
Q "SELECT * FROM information_schema.tablets WHERE TABLE_NAME='vt' LIMIT 1\G" 2>&1 | grep -iE "VERSION|STATE|ROWCOUNT" | head -20

echo ""
echo "############ 查看 BE 的 compaction 状态页（关键：累积的 rowset 数）############"
docker exec doris-learn curl -s "http://127.0.0.1:8040/api/compaction/show?tablet_id=$TID2" 2>&1 | head -5
echo ""
echo "--- 单行 INSERT 那张表的 compaction ---"
docker exec doris-learn curl -s "http://127.0.0.1:8040/api/compaction/show?tablet_id=$TID" 2>&1 | head -5
