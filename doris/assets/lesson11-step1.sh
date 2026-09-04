#!/bin/bash
# 课 11 步骤 1：知识点 1 —— Schema Change 的异步执行特性
# 用法：bash lesson11-step1.sh（需先跑 lesson11-setup.sh）
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
# 取最后一条（最新）Schema Change 作业的状态
sc_state() { q "SHOW ALTER TABLE COLUMN FROM shop\G" | grep -E "^ +State:" | awk '{print $2}' | tail -1; }

echo "##################################################################"
echo "# 1.1 先看两张表的 light_schema_change 开关差异                    #"
echo "##################################################################"
q "SHOW CREATE TABLE sc_light\G" | grep -iE "light_schema_change"
q "SHOW CREATE TABLE sc_heavy\G" | grep -iE "light_schema_change"

echo ""
echo "##################################################################"
echo "# 1.2 Light 表加列：ALTER 返回后能不能立刻查到新列？                #"
echo "##################################################################"
S=$(date +%s%N)
q "ALTER TABLE sc_light ADD COLUMN remark VARCHAR(100) DEFAULT 'light-ok';"
E=$(date +%s%N)
echo "  >> ALTER 语句返回耗时: $(( (E-S)/1000000 )) ms"
echo "--- 不等，立刻查新列 ---"
q "SELECT id, dt, amount, remark FROM sc_light WHERE id = 1;"
echo "  >> 结论：light 表 ALTER 返回即可查（500 万行实测 271-304 ms 完成）"

echo ""
echo "##################################################################"
echo "# 1.3 Heavy 表加列：同样操作，结果一样吗？                          #"
echo "##################################################################"
S=$(date +%s%N)
q "ALTER TABLE sc_heavy ADD COLUMN remark VARCHAR(100) DEFAULT 'heavy-ok';"
E=$(date +%s%N)
echo "  >> ALTER 语句返回耗时: $(( (E-S)/1000000 )) ms  <-- 注意：返回了！"
echo "--- 不等，立刻查新列（这里会报错，报错原文必须保留）---"
q "SELECT id, dt, amount, remark FROM sc_heavy WHERE id = 1;"
echo "  >> 这就是本课的认知冲突点：ALTER 返回 ≠ 改完了"

echo ""
echo "##################################################################"
echo "# 1.4 SHOW ALTER TABLE COLUMN 看异步作业状态                       #"
echo "##################################################################"
echo "--- 刚提交时 ---"
q "SHOW ALTER TABLE COLUMN FROM shop\G" | awk -v RS='***************************' '/TableName: sc_heavy/{print}' | grep -E "JobId|TableName|State|Progress|TransactionId"
echo "--- 轮询直到 FINISHED ---"
SS=$(date +%s)
for i in $(seq 1 120); do
  ST=$(sc_state)
  echo "  t=${i}s State=$ST"
  [ "$ST" = "FINISHED" ] && break
  [ "$ST" = "CANCELLED" ] && break
  sleep 1
done
EE=$(date +%s)
echo "  >> 从提交到 FINISHED 共 $((EE-SS)) 秒"
echo "--- 再查新列（现在能查到了）---"
q "SELECT id, dt, amount, remark FROM sc_heavy WHERE id = 1;"

echo ""
echo "##################################################################"
echo "# 1.5 支持矩阵实测：哪些改法能过，哪些直接被拒绝                     #"
echo "##################################################################"
echo "--- A. 加列（末尾）---"
q "ALTER TABLE sc_light ADD COLUMN a1 INT DEFAULT '1';"
echo "  结果: 通过"

echo "--- B. 加列并指定位置（AFTER）---"
q "ALTER TABLE sc_light ADD COLUMN a2 INT DEFAULT '2' AFTER amount;"
echo "  结果: 通过"

echo "--- C. 加 AGGREGATE 列到 Aggregate 表（先建一张）---"
q "DROP TABLE IF EXISTS sc_agg;" >/dev/null 2>&1
q "CREATE TABLE sc_agg (
     dt      DATE,
     user_id INT,
     cnt     BIGINT SUM DEFAULT '0'
   )
   AGGREGATE KEY(dt, user_id)
   DISTRIBUTED BY HASH(user_id) BUCKETS 4
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO sc_agg SELECT '2026-01-01', number, 1 FROM numbers('number' = '100000');"
sleep 2
q "ALTER TABLE sc_agg ADD COLUMN amt DECIMAL(10,2) SUM DEFAULT '0';"
sleep 2
q "SELECT dt, user_id, cnt, amt FROM sc_agg WHERE user_id = 1;"

echo "--- D. 改列类型：INT -> BIGINT（加宽，允许）---"
q "DROP TABLE IF EXISTS sc_mod;" >/dev/null 2>&1
q "CREATE TABLE sc_mod (id INT, v INT) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num' = '1');"
q "INSERT INTO sc_mod SELECT number, number FROM numbers('number' = '100000');"
sleep 2
q "ALTER TABLE sc_mod MODIFY COLUMN v BIGINT;"
sleep 2
q "DESC sc_mod;" | grep -E "^v"

echo "--- E. 缩短 VARCHAR 长度（禁止！报错原文）---"
q "DROP TABLE IF EXISTS sc_len;" >/dev/null 2>&1
q "CREATE TABLE sc_len (k VARCHAR(100), v INT) DUPLICATE KEY(k)
   DISTRIBUTED BY HASH(k) BUCKETS 2 PROPERTIES ('replication_num' = '1');"
q "ALTER TABLE sc_len MODIFY COLUMN k VARCHAR(20);"
echo "  ^^^ 报错原文：Shorten type length is prohibited"

echo "--- F. 跨类型修改 INT -> VARCHAR（禁止！报错原文）---"
q "ALTER TABLE sc_mod MODIFY COLUMN id VARCHAR(10);"
echo "  ^^^ 报错原文：Can not change from wider type int to narrower type varchar(10)"

echo "--- G. 改 Key 顺序（ORDER BY 必须写全所有列）---"
q "DROP TABLE IF EXISTS sc_key;" >/dev/null 2>&1
q "CREATE TABLE sc_key (id INT, dt DATE, v INT) DUPLICATE KEY(id, dt)
   DISTRIBUTED BY HASH(id) BUCKETS 2 PROPERTIES ('replication_num' = '1');"
q "INSERT INTO sc_key SELECT number, '2026-01-01', number FROM numbers('number' = '100000');"
sleep 2
echo "  先写一个不完整的（会报错）:"
q "ALTER TABLE sc_key ORDER BY (dt, id);"
echo "  ^^^ 报错原文：Reorder stmt should contains all columns"
echo "  再写完整的（通过）:"
q "ALTER TABLE sc_key ORDER BY (dt, id, v);"
sleep 2
q "DESC sc_key;"

echo "--- H. 无分区表改分桶数（禁止！报错原文）---"
q "ALTER TABLE sc_light MODIFY DISTRIBUTION DISTRIBUTED BY HASH(id) BUCKETS 8;"
echo "  ^^^ 报错原文：Only support change partitioned table's distribution"

echo "--- I. 删列 ---"
q "ALTER TABLE sc_light DROP COLUMN a1;"
sleep 2
q "DESC sc_light;"

echo ""
echo "##################################################################"
echo "# 1.6 一张表同时跑两个 Schema Change：能不能并发？                  #"
echo "##################################################################"
q "ALTER TABLE sc_light ADD COLUMN m1 INT DEFAULT '1';"
q "ALTER TABLE sc_light ADD COLUMN m2 INT DEFAULT '2';"
sleep 3
q "SELECT id, m1, m2 FROM sc_light WHERE id = 1;"
echo "  >> 两条都生效了（Doris 内部串行处理，不像备份作业那样互斥）"

echo ""
echo "##################################################################"
echo "# 1.7 重量级 Schema Change 期间：还能不能导入？                     #"
echo "##################################################################"
echo "--- sc_heavy 灌新数据（用旧列，不用刚加的 remark）---"
q "INSERT INTO sc_heavy (id, dt, amount) VALUES (99999999, '2026-06-01', 123.45);"
echo "  >> 导入没被阻塞（Doris 会把导入也挂到 schema change 的调度里）"
echo "--- 等作业结束 ---"
for i in $(seq 1 60); do
  ST=$(sc_state)
  [ "$ST" = "FINISHED" ] && break
  [ "$ST" = "CANCELLED" ] && break
  sleep 1
done
echo "  作业 State=$ST"
echo "--- 确认新增行在，且新列自动补上了默认值 ---"
q "SELECT id, dt, amount, remark FROM sc_heavy WHERE id = 99999999;"

echo ""
echo "##################################################################"
echo "# 1.8 CANCEL：改错了怎么撤                                          #"
echo "##################################################################"
echo "  语法：CANCEL ALTER TABLE COLUMN FROM <db>.<table>;"
echo "  ⚠️ 注意：4.1.3 不支持 'WHERE JobId = xxx' 的写法，会报"
echo "     mismatched input 'WHERE' expecting {<EOF>, ';'}"
echo ""
q "DROP TABLE IF EXISTS sc_cancel;" >/dev/null 2>&1
q "CREATE TABLE sc_cancel (id INT, v INT) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2
   PROPERTIES ('replication_num' = '1', 'light_schema_change' = 'false');"
q "INSERT INTO sc_cancel SELECT number, number FROM numbers('number' = '1000000');"
sleep 3
q "ALTER TABLE sc_cancel ADD COLUMN big VARCHAR(100) DEFAULT 'zz';"
sleep 3
echo "--- 作业已完成，此时 CANCEL 会报什么？---"
q "CANCEL ALTER TABLE COLUMN FROM shop.sc_cancel;"
echo "  ^^^ 报错原文：Table[sc_cancel] is not under SCHEMA_CHANGE."
echo "  >> 这个报错本身就是信息：作业跑完了就撤不回来，CANCEL 只对进行中的作业有效"
echo "--- 列已经加上了 ---"
q "DESC sc_cancel;"

echo ""
echo "--- 那什么时候才撤得回？看 WAITING_TXN 状态 ---"
cat <<'EOF'
  🟡 单机边界：本机的加列作业 1-3 秒就跑完了，脚本来不及在"进行中"发出 CANCEL，
     所以这里演示的是 CANCEL 的失败面（作业已完成）。

  真实生产里能撤回来的场景，是作业卡在 WAITING_TXN：
    1. 有一笔导入事务长时间没提交
    2. 此时 ALTER 会停在 WAITING_TXN，等这笔事务结束
    3. 这时候 CANCEL ALTER TABLE COLUMN FROM db.tbl; 就能撤

  复现办法（读者可自行尝试）：
    会话 A:  BEGIN;
             INSERT INTO sc_cancel VALUES (77777777, 777);
             SELECT SLEEP(30);        -- 故意不提交
    会话 B:  ALTER TABLE sc_cancel ADD COLUMN x INT DEFAULT '1';
             SHOW ALTER TABLE COLUMN FROM shop;   -- 看到 State = WAITING_TXN
             CANCEL ALTER TABLE COLUMN FROM shop.sc_cancel;   -- 此时能撤
  本机实测：WAITING_TXN 只持续约 1 秒就转 FINISHED（数据量小、事务随即提交），
           所以 CANCEL 时机极窄 —— 这恰恰说明单机实验和生产的差距。
EOF

echo ""
echo "--- 另一个真实错误：作业还在跑时改表结构 ---"
q "DROP TABLE IF EXISTS sc_busy;" >/dev/null 2>&1
q "CREATE TABLE sc_busy (id INT, v INT) DUPLICATE KEY(id)
   DISTRIBUTED BY HASH(id) BUCKETS 2
   PROPERTIES ('replication_num' = '1', 'light_schema_change' = 'false');"
q "INSERT INTO sc_busy SELECT number, number FROM numbers('number' = '2000000');"
sleep 4
echo "  先发起一个 schema change..."
q "ALTER TABLE sc_busy ADD COLUMN c1 INT DEFAULT '1';" >/dev/null 2>&1
echo "  不等它完成，立刻再做一次 ALTER（会报什么？）:"
q "ALTER TABLE sc_busy SET ('replication_num' = '2');"
echo "  ^^^ 报错原文：Table[sc_busy]'s state(SCHEMA_CHANGE) is not NORMAL. Do not allow doing ALTER ops"
echo "  >> 含义：表在 SCHEMA_CHANGE 状态期间，不能再接受别的 ALTER"


echo ""
echo "##################################################################"
echo "# 1.9 小结：支持矩阵                                                #"
echo "##################################################################"
cat <<'EOF'
  ┌─────────────────────┬────────────┬──────────────────────────────┐
  │ 操作                │ 是否支持   │ 备注 / 报错原文              │
  ├─────────────────────┼────────────┼──────────────────────────────┤
  │ 末尾加列            │ ✅ 支持    │ light 下毫秒级               │
  │ 指定位置加列        │ ✅ 支持    │ AFTER col                    │
  │ 删列                │ ✅ 支持    │                              │
  │ 改列名              │ ✅ 支持    │ RENAME（本脚本未演示）       │
  │ 加宽类型 INT→BIGINT │ ✅ 支持    │ 只许加宽                     │
  │ VARCHAR 加长        │ ✅ 支持    │ 50→100 可以                  │
  │ VARCHAR 缩短        │ ❌ 拒绝    │ Shorten type length is prohibited │
  │ 跨类型修改          │ ❌ 拒绝    │ Can not change from wider... │
  │ 改 Key 顺序         │ ✅ 支持    │ 必须写全所有列，否则报       │
  │                     │            │ Reorder stmt should contains all columns │
  │ 改分桶数（无分区表）│ ❌ 拒绝    │ Only support change partitioned table's │
  │ 改分桶数（分区表）  │ ✅ 支持    │ 详见 step1 扩展（本脚本略）  │
  │ 改副本数            │ ⚠️ 受限    │ 受 BE 数量与反亲和约束       │
  └─────────────────────┴────────────┴──────────────────────────────┘
EOF

echo ""
echo "===== step1 完成 ====="
echo "  下一步：bash lesson11-step2.sh （知识点 2：备份与恢复）"
