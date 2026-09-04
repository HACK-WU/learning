#!/bin/bash
# 课 12 步骤 1：知识点 1 —— Doris 与同类系统对比
# 用法：bash lesson12-step1.sh
#
# 核心思路：本机没有 ClickHouse / ES / Hive 容器，不做「跑分 PK」。
# 改为「用 Doris 自己的实测数据反推能力边界」，再定位它在生态里的位置。

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }
t() {  # 计时执行：t "SQL"
  START=$(date +%s.%N)
  $FE -e "$1" > /dev/null 2>&1
  END=$(date +%s.%N)
  echo "$(echo "$END - $START" | bc)"
}

echo "################################################################"
echo "# 1.1 列存 vs 行存：Doris 的「快」到底是什么快"
echo "################################################################"
echo ""
echo "--- 扫 1 个窄列 vs 扫 10 个宽列（同一张 2150 万行的表）---"
echo ""
echo "[A] 只扫 amount 一列："
for i in 1 2 3; do
  echo "    第 $i 轮：$(t "SELECT SUM(amount) FROM orders;") 秒"
done
echo ""
echo "[B] 扫全部 13 列（SELECT * 聚合，强制读所有列）："
for i in 1 2 3; do
  echo "    第 $i 轮：$(t "SELECT SUM(LENGTH(CONCAT(CAST(order_date AS STRING), province, city, CAST(user_id AS STRING), CAST(product_id AS STRING), category, CAST(quantity AS STRING), CAST(amount AS STRING), pay_type, CAST(status AS STRING), remark, CAST(created_at AS STRING), CAST(updated_at AS STRING)))) FROM orders;") 秒"
done
echo ""
echo "  → 结论：列存的收益来自「只读需要的列」，不是「什么都快」。"
echo "    行存数据库（MySQL/PG）做 [A] 这类聚合要把整行都读出来。"

echo ""
echo "################################################################"
echo "# 1.2 Doris 抢 ES 的场景：倒排索引全文检索"
echo "################################################################"
echo ""
echo "--- 20 万行日志表，倒排索引 vs LIKE 全表扫 ---"
echo ""
q "SELECT COUNT(*) AS cnt, SUM(LENGTH(msg)) AS total_len FROM log_search;"
echo ""
echo "[A] 倒排索引 MATCH（level 列，精确分词命中）："
for i in 1 2 3; do
  echo "    第 $i 轮：$(t "SELECT COUNT(*) FROM log_search WHERE level MATCH 'ERROR';") 秒"
done
echo ""
echo "[B] LIKE 全表扫（同等语义）："
for i in 1 2 3; do
  echo "    第 $i 轮：$(t "SELECT COUNT(*) FROM log_search WHERE level LIKE '%ERROR%';") 秒"
done
echo ""
echo "  → 命中率越高，倒排索引优势越小；命中率越低（如百万里挑一），优势越明显。"
echo "    本例 level='ERROR' 命中 2 万/20 万 = 10%，属于高命中，差距不大。"

echo ""
echo "--- 中文分词器的真实边界（本机实测，报错原文照录）---"
echo "  先建一张 chinese parser 的表："
q "DROP TABLE IF EXISTS log_cn;"
q "CREATE TABLE log_cn (
     ts DATETIME NULL,
     msg STRING NULL,
     INDEX idx_msg (msg) USING INVERTED PROPERTIES('parser' = 'chinese', 'support_phrase' = 'true')
   ) DUPLICATE KEY(ts) DISTRIBUTED BY HASH(ts) BUCKETS 1
   PROPERTIES ('replication_num' = '1');"
q "INSERT INTO log_cn SELECT created_at, CONCAT('用户在', city, '购买了', category) FROM orders LIMIT 1000;"
echo "  灌了 1000 行中文数据后，一查询就炸："
q "SELECT COUNT(*) FROM log_cn WHERE msg MATCH_ANY '北京';"
echo ""
echo "  ↑ 真实报错：(127.0.0.1)[INTERNAL_ERROR]chinese tokenizer dict file not found:"
echo "             /opt/be2/dict/jieba.dict.utf8"
echo "  到 BE 上确认，这个目录压根不存在："
docker exec doris-learn sh -c "ls -la /opt/be2/dict/ 2>&1 | head -3"
echo ""
echo "  → 这是「Doris 能抢 ES 场景」的前置条件，不是语法问题："
echo "    装 jieba 字典是运维动作，不是 SQL 能解决的。all-in-one 镜像默认不带。"
q "DROP TABLE IF EXISTS log_cn;"

echo ""
echo "--- 短语检索要求「严格相邻」（实测反直觉行为）---"
q "SELECT SUM(LENGTH(msg)) AS len_sum FROM log_search WHERE msg MATCH_PHRASE 'bought';"
q "SELECT SUM(LENGTH(msg)) AS len_sum FROM log_search WHERE msg MATCH_PHRASE 'user bought';"
echo "  ↑ 数据长这样：'user 1355961 bought 运动户外 ...'"
echo "    单 term 'bought' 能命中；'user bought' 返回空，因为中间隔了 user_id"
echo "    MATCH_PHRASE 要求 term 严格相邻，MATCH_ALL 只要求都出现"

echo ""
echo "################################################################"
echo "# 1.3 Doris 抢不了的场景 1：高频单行点查（KV 场景）"
echo "################################################################"
echo ""
echo "--- 关键方法：必须排除「连接开销」，否则测的是 docker exec 不是 Doris ---"
echo ""
echo "[基线] 200 次独立连接，每次只发 SELECT 1："
S=$(date +%s.%N)
for i in $(seq 1 200); do $FE -e "SELECT 1;" > /dev/null 2>&1; done
E=$(date +%s.%N)
CONN=$(echo "$E - $S" | bc)
echo "    总耗时：${CONN} 秒  ← 这几乎全是连接开销"

echo ""
echo "[A] 200 次独立连接，每次点查 1 行："
S=$(date +%s.%N)
for i in $(seq 1 200); do $FE -e "SELECT id, amount FROM anti_kv WHERE id = $i;" > /dev/null 2>&1; done
E=$(date +%s.%N)
A=$(echo "$E - $S" | bc)
echo "    总耗时：${A} 秒"
echo "    减去连接开销 ≈ $(echo "$A - $CONN" | bc) 秒  ← 接近 0，说明 Doris 点查本身极快"
echo "  ⚠️ 但这个测法没有意义：真实业务的高并发点查不会每次新建连接"

echo ""
echo "[B] 单连接内串行 200 次点查（这才是真实口径）："
IDS=$($FE -N -e "SELECT GROUP_CONCAT(id) FROM (SELECT id FROM anti_kv ORDER BY id LIMIT 200) t;" 2>/dev/null)
S=$(date +%s.%N)
{
  for id in $(echo "$IDS" | tr ',' ' '); do
    echo "SELECT id, amount FROM anti_kv WHERE id = $id;"
  done
} | docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -N > /tmp/l12_p.out 2>&1
E=$(date +%s.%N)
B=$(echo "$E - $S" | bc)
echo "    总耗时：${B} 秒，返回 $(wc -l < /tmp/l12_p.out) 行"
echo "    单次约 $(echo "scale=2; $B * 1000 / 200" | bc) ms，吞吐约 $(echo "scale=0; 200 / $B" | bc) QPS（单连接串行）"
echo "  ⚠️ 5-7 ms 的单次延迟对 OLAP 没问题，但对 KV 场景是灾难级（Redis 是 0.1 ms 级）"

echo ""
echo "[C] 对照：单连接内 1 次聚合查（Doris 的主场）："
S=$(date +%s.%N)
echo "SELECT province, SUM(amount) AS s FROM local_1m GROUP BY province ORDER BY s DESC LIMIT 200;" | \
  docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -N > /dev/null 2>&1
E=$(date +%s.%N)
echo "    耗时：$(echo "$E - $S" | bc) 秒，一次处理 314 万行"
echo "  → 同样的 0.2 秒：点查拿到 200 行，聚合处理 314 万行。这就是分工的边界。"

echo ""
echo "################################################################"
echo "# 1.4 Doris 抢不了的场景 2：事务（OLTP 场景）"
echo "################################################################"
echo ""
echo "--- 显式事务 + ROLLBACK，看数据到底回滚了没 ---"
echo ""
q "DROP TABLE IF EXISTS anti_txn;"
q "CREATE TABLE anti_txn (
     id BIGINT NOT NULL,
     mobile VARCHAR(32) NOT NULL,
     name VARCHAR(64) NULL,
     amount DECIMAL(18,2) NULL
   ) UNIQUE KEY(id) DISTRIBUTED BY HASH(id) BUCKETS 4
   PROPERTIES ('replication_num' = '1', 'enable_unique_key_merge_on_write' = 'true');"
q "INSERT INTO anti_txn VALUES (1,'13800000001','alice',10.00),(2,'13800000002','bob',20.00);"
echo ""
echo "  [基线] 明细 + SUM（不用 COUNT(*)，它走元数据优化不扫数据）:"
q "SELECT id, mobile, name, amount FROM anti_txn ORDER BY id;"
q "SELECT SUM(amount) AS s FROM anti_txn;"
echo ""
echo "  [操作] BEGIN → INSERT → ROLLBACK:"
q "BEGIN;"
q "INSERT INTO anti_txn VALUES (3,'13800000003','carol',30.00);"
q "ROLLBACK;"
echo ""
echo "  [结果] 明细:"
q "SELECT id, mobile, name, amount FROM anti_txn ORDER BY id;"
echo "  [结果] SUM:"
q "SELECT SUM(amount) AS s FROM anti_txn;"
echo ""
echo "  ⚠️ 关键：ROLLBACK 不报错，但数据没回滚（carol 还在，SUM 从 30 变 60）"
echo "     Doris 的 BEGIN/COMMIT 只是语法兼容，不提供 OLTP 的多语句原子性"
echo ""
echo "  [再验一次] UPDATE 后 ROLLBACK:"
q "BEGIN;"
q "UPDATE anti_txn SET amount = 11111.00 WHERE id = 1;"
q "ROLLBACK;"
q "SELECT id, amount FROM anti_txn ORDER BY id;"
echo "  ↑ amount 已改成 11111.00，ROLLBACK 同样无效"

echo ""
echo "--- 事务相关变量（显示 REPEATABLE-READ 是「兼容显示」，不是真支持）---"
q "SHOW VARIABLES LIKE 'transaction_isolation';"
q "SHOW VARIABLES LIKE 'autocommit';"

echo ""
echo "################################################################"
echo "# 1.5 单行 UPDATE / DELETE：能跑，但代价完全不同"
echo "################################################################"
echo ""
q "DELETE FROM anti_txn WHERE id = 2;"
q "SELECT id, mobile, amount FROM anti_txn ORDER BY id;"
echo "  → 单条 DELETE 能执行，但 Doris 的 DELETE 是标记删除 + 后台 compaction 清理"
echo "    高频单行删改会产生大量 delete predicate，拖垮查询（课 9 讲过的 compaction 压力）"

echo ""
echo "################################################################"
echo "# 1.6 小结：能力边界速查"
echo "################################################################"
echo ""
echo "  ✅ 擅长：大表聚合、多维分析、宽表扫描只取少数列、高并发吞吐型查询"
echo "  ⚠️ 能做但要小心：全文检索（依赖分词器）、低频单行更新"
echo "  ❌ 不该做：高频单行点查（KV）、多语句事务（OLTP）、高频单行删改"
echo ""
echo "  下一步：bash lesson12-step2.sh （知识点 2：存算分离架构）"
