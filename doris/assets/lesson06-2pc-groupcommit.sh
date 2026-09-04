#!/bin/bash
Q() { docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop --batch -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
mkdir -p /tmp/loadlab

echo "############ 实验 A：Group Commit 的实测效果（多行 VALUES 模拟高频小批量）############"
echo "--- A1: 建两张表，一张开启 group commit(100ms)，一张不走 ---"
Q "DROP TABLE IF EXISTS gc_on"
Q "DROP TABLE IF EXISTS gc_off"
Q "CREATE TABLE gc_on (id BIGINT, val VARCHAR(32)) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1
   PROPERTIES ('replication_num'='1', 'group_commit_interval_ms'='100')"
Q "CREATE TABLE gc_off (id BIGINT, val VARCHAR(32)) DUPLICATE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 1
   PROPERTIES ('replication_num'='1', 'group_commit_interval_ms'='10000')"

echo ""
echo "--- A2: 100 次单行 INSERT 到 gc_on ---"
S=$(date +%s.%N)
for i in $(seq 1 100); do
  Q "INSERT INTO gc_on VALUES ($i,'g$i')" > /dev/null 2>&1
done
E=$(date +%s.%N)
GC_ON=$(echo "$E - $S" | bc)
echo "gc_on（group_commit_interval_ms=100）100 次单行 INSERT: ${GC_ON} 秒"

echo ""
echo "--- A3: 100 次单行 INSERT 到 gc_off ---"
S2=$(date +%s.%N)
for i in $(seq 1 100); do
  Q "INSERT INTO gc_off VALUES ($i,'g$i')" > /dev/null 2>&1
done
E2=$(date +%s.%N)
GC_OFF=$(echo "$E2 - $S2" | bc)
echo "gc_off（group_commit_interval_ms=10000）100 次单行 INSERT: ${GC_OFF} 秒"

echo ""
echo "--- A4: 行数核对 ---"
Q "SELECT 'gc_on' AS t, COUNT(*) AS c FROM gc_on UNION ALL SELECT 'gc_off', COUNT(*) FROM gc_off"

echo ""
echo "############ 实验 B：Stream Load 两阶段提交（Two-Phase Commit）############"
echo "--- B1: 开启两阶段提交，导入后先 prepare ---"
Q "TRUNCATE TABLE load_demo"
docker exec doris-learn curl -s --location-trusted -u root: \
  -H "label:sl_2pc_$RANDOM" \
  -H "column_separator:," \
  -H "format:csv" \
  -H "two_phase_commit:true" \
  -T /tmp/loadlab/orders_10k.csv \
  "http://127.0.0.1:8030/api/shop/load_demo/_stream_load" | tee /tmp/loadlab/r2pc.json | grep -E '"(TxnId|Status|Label|TwoPhaseCommit|Message)"'
echo ""
echo "--- B2: prepare 后查数据（应仍为 0，因为未 commit）---"
Q "SELECT COUNT(*) AS rows_before_commit FROM load_demo"

echo ""
echo "--- B3: 提取 TxnId 并 commit ---"
TXN=$(grep '"TxnId"' /tmp/loadlab/r2pc.json | sed 's/[^0-9]*\([0-9]*\).*/\1/')
echo "提取到的 TxnId: $TXN"
if [ -n "$TXN" ] && [ "$TXN" != "-1" ]; then
  docker exec doris-learn curl -s -X PUT --location-trusted -u root: \
    -H "txn_id:$TXN" \
    -H "txn_operation:commit" \
    "http://127.0.0.1:8030/api/shop/load_demo/_stream_load_2pc"
  echo ""
else
  echo "未拿到有效 TxnId，跳过 commit"
fi

echo ""
echo "--- B4: commit 后查数据（应变 10000）---"
sleep 3
Q "SELECT COUNT(*) AS rows_after_commit FROM load_demo"

echo ""
echo "############ 实验 C：唯一键表的 UPSERT 语义（导入即更新）############"
Q "DROP TABLE IF EXISTS uniq_load_demo"
Q "CREATE TABLE uniq_load_demo (
    order_id BIGINT,
    province VARCHAR(32),
    amount DECIMAL(10,2)
) UNIQUE KEY(order_id) DISTRIBATED_PLACEHOLDER"
# 上面故意写错，下面用正确语句
Q "DROP TABLE IF EXISTS uniq_load_demo"
Q "CREATE TABLE uniq_load_demo (
    order_id BIGINT,
    province VARCHAR(32),
    amount DECIMAL(10,2)
) UNIQUE KEY(order_id) DISTRIBUTED BY HASH(order_id) BUCKETS 2
PROPERTIES ('replication_num'='1')"

echo "--- C1: 导入 3 行 ---"
docker exec doris-learn bash -c "printf '1,广东,100.00\n2,山东,200.00\n3,江苏,300.00\n' > /tmp/loadlab/uniq1.csv"
docker exec doris-learn curl -s --location-trusted -u root: -H "label:uq_1_$RANDOM" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/uniq1.csv "http://127.0.0.1:8030/api/shop/uniq_load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows)"'
Q "SELECT * FROM uniq_load_demo ORDER BY order_id"

echo ""
echo "--- C2: 再导入同 order_id 但不同值（应覆盖更新）---"
docker exec doris-learn bash -c "printf '1,北京,999.99\n4,浙江,400.00\n' > /tmp/loadlab/uniq2.csv"
docker exec doris-learn curl -s --location-trusted -u root: -H "label:uq_2_$RANDOM" -H "column_separator:," -H "format:csv" \
  -T /tmp/loadlab/uniq2.csv "http://127.0.0.1:8030/api/shop/uniq_load_demo/_stream_load" | grep -E '"(Status|NumberLoadedRows)"'
Q "SELECT * FROM uniq_load_demo ORDER BY order_id"
