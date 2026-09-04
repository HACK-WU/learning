#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
mkdir -p /tmp/loadlab

echo "############ 实验 A：小批量写入如何制造 tablet 版本堆积 ############"
Q "DROP TABLE IF EXISTS version_demo"
Q "CREATE TABLE version_demo (
    id BIGINT, val VARCHAR(32)
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ('replication_num' = '1')"

echo ""
echo "--- A1: 连续 30 次单行 INSERT，观察版本数 ---"
for i in $(seq 1 30); do
  Q "INSERT INTO version_demo VALUES ($i, 'v$i')" > /dev/null 2>&1
done
echo "30 次单行 INSERT 完成"
Q "SHOW TABLETS FROM version_demo" | awk -F'\t' 'NR==1{print "版本数(VisibleVersionCount):"; } NR>1{print "  tablet="$1" VisibleVersionCount="$15" VersionCount="$16}'

echo ""
echo "--- A2: 单次批量 INSERT 30 行，再观察版本数 ---"
Q "TRUNCATE TABLE version_demo"
VALS=""
for i in $(seq 1 30); do
  if [ -n "$VALS" ]; then VALS="$VALS,"; fi
  VALS="$VALS($i,'v$i')"
done
Q "INSERT INTO version_demo VALUES $VALS"
echo "批量 INSERT 完成"
Q "SHOW TABLETS FROM version_demo" | awk -F'\t' 'NR>1{print "  tablet="$1" VisibleVersionCount="$15" VersionCount="$16}'

echo ""
echo "############ 实验 B：Group Commit —— 小批量写入的救赎 ############"
echo "--- B1: 查看表的 group commit 配置（建表时默认开启）---"
Q "SHOW CREATE TABLE version_demo" | grep -i "group_commit"

echo ""
echo "--- B2: 建一张开启 group commit 的表 ---"
Q "DROP TABLE IF EXISTS gc_demo"
Q "CREATE TABLE gc_demo (
    id BIGINT, val VARCHAR(32)
) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ('replication_num' = '1', 'group_commit_interval_ms' = '3000')"

echo ""
echo "--- B3: 连续 20 次单行 INSERT 到 gc_demo，测总耗时 ---"
S=$(date +%s.%N)
for i in $(seq 1 20); do
  Q "INSERT INTO gc_demo VALUES ($i, 'g$i')" > /dev/null 2>&1
done
E=$(date +%s.%N)
echo "20 次单行 INSERT（group_commit_interval_ms=3000）耗时: $(echo "$E - $S" | bc) 秒"
Q "SELECT COUNT(*) AS gc_rows FROM gc_demo"

echo ""
echo "--- B4: 对照组：同样 20 次单行 INSERT 到普通表 ---"
Q "TRUNCATE TABLE version_demo"
S2=$(date +%s.%N)
for i in $(seq 1 20); do
  Q "INSERT INTO version_demo VALUES ($i, 'g$i')" > /dev/null 2>&1
done
E2=$(date +%s.%N)
echo "20 次单行 INSERT（无 group commit）耗时: $(echo "$E2 - $S2" | bc) 秒"
Q "SELECT COUNT(*) AS normal_rows FROM version_demo"

echo ""
echo "############ 实验 C：三种写入方式的行数/耗时/版本数总表 ############"
echo "--- C1: Stream Load 一次 1 万行的版本数 ---"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_ver_$RANDOM" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/orders_10k.csv \
  "http://127.0.0.1:8030/api/shop/load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows)"'
Q "SHOW TABLETS FROM load_demo" | awk -F'\t' 'NR>1{sum+=$15; n++} END{print "Stream Load 后平均 VisibleVersionCount: " sum/n " (tablet 数=" n ")"}'

echo ""
echo "--- C2: 1000 次单行 INSERT 后的版本数 ---"
Q "TRUNCATE TABLE version_demo"
for i in $(seq 1 200); do
  Q "INSERT INTO version_demo VALUES ($i, 'x')" > /dev/null 2>&1
done
Q "SHOW TABLETS FROM version_demo" | awk -F'\t' 'NR>1{print "200 次单行 INSERT 后 VisibleVersionCount=" $15 " VersionCount=" $16}'
