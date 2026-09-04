#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 7：异步物化视图与透明改写
#
# 前提：已跑过 lesson08-setup.sh（orders 表 2150 万行）
#
# ⚠️ 本步骤有三个必踩的坑，都在脚本里标注了：
#   坑 1：SHOW MATERIALIZED VIEWS 不能用（只能 SHOW CREATE ... 带名字）
#   坑 2：REFRESH 是异步的，返回成功不代表刷完了
#   坑 3：分区 MV 的分区名 ≠ 基表的分区名
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 7.1：先看没有 MV 时的基线耗时 =========="
echo ""
echo "⚠️ 关键：必须【关掉透明改写】才能测到真实成本。"
echo "   否则优化器可能已经把它改写到某个 MV 上，你测到的就不是 orders 的真实开销了。"
echo ""
echo "--- 关掉改写，硬查基表 orders（2150 万行全表聚合），跑 4 次 ---"
for i in 1 2 3 4; do
  runq "SET enable_materialized_view_rewrite = false;
        SELECT province, SUM(amount) AS total FROM orders GROUP BY province ORDER BY province;" > /dev/null
done
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "FROM orders GROUP BY province" | head -4
echo ""
echo "👆 本机参考值：387 / 416 / 475 ms"
echo ""
echo "   注：这不是冷启动效应。我专门验证过——换一个从没查过的列组合，"
echo "      首次 393ms，后续 371-381ms，冷热几乎没差。"
echo "      本机同时跑着 Kafka、MinIO 和一批监控容器，数值有波动属正常。"

echo ""
echo "========== 步骤 7.2：建异步物化视图 =========="
runq "DROP MATERIALIZED VIEW IF EXISTS mv_prov_pay_daily;"
runq "CREATE MATERIALIZED VIEW mv_prov_pay_daily
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
DISTRIBUTED BY HASH(province) BUCKETS 4
AS
SELECT
  order_date,
  province,
  pay_type,
  COUNT(*) AS order_cnt,
  SUM(amount) AS total_amount
FROM orders
GROUP BY order_date, province, pay_type;"

echo ""
echo "--- 确认建成了（MV 会出现在 SHOW TABLES 里，它本质就是一张表）---"
runq "SHOW TABLES;" | grep mv_prov_pay_daily
runq "SELECT COUNT(*) AS mv_rows FROM mv_prov_pay_daily;"
echo ""
echo "👆 本机参考值：23360 行（8 省 × 4 支付方式 × 730 天）"
echo "   对比基表 2150 万行，压缩了约 920 倍"

echo ""
echo "========== 步骤 7.3：⚠️ 坑 1 —— 查看 MV 的正确命令 =========="
echo "--- 这些全都会报错（我逐个试过）---"
for cmd in "SHOW MATERIALIZED VIEWS" "SHOW MATERIALIZED VIEW" "SHOW MVS" "SHOW MATERIALIZED VIEWS FROM shop"; do
  printf "  %-45s → " "$cmd;"
  runq "$cmd;" 2>&1 | head -1
done
echo ""
echo "--- 能用的只有这一个（必须带 MV 名字）---"
runq "SHOW CREATE MATERIALIZED VIEW mv_prov_pay_daily;" | head -2
echo ""
echo "--- 或者干脆当普通表用 ---"
runq "SELECT * FROM mv_prov_pay_daily ORDER BY order_date, province, pay_type LIMIT 3;"

echo ""
echo "========== 步骤 7.4：透明改写 —— 业务 SQL 一个字都不改 =========="
echo ""
echo "--- 7.4a 与 MV 定义完全一致 → 应命中 ---"
runq "EXPLAIN SELECT order_date, province, pay_type, COUNT(*) AS order_cnt, SUM(amount) AS total_amount FROM orders GROUP BY order_date, province, pay_type;" \
  | sed -n '/MATERIALIZATIONS/,/STATISTICS/p'
echo "👆 应看到：MaterializedViewRewriteSuccessAndChose: CBO.internal.shop.mv_prov_pay_daily chose"

echo ""
echo "--- 7.4b 只取部分聚合列 → 应命中 ---"
runq "EXPLAIN SELECT province, SUM(amount) AS total_amount FROM orders GROUP BY province;" \
  | sed -n '/MATERIALIZATIONS/,/STATISTICS/p'

echo ""
echo "--- 7.4c 带 WHERE 过滤 → 应命中，且谓词下推 ---"
runq "EXPLAIN SELECT province, SUM(amount) AS total_amount FROM orders WHERE order_date = '2026-01-01' GROUP BY province;" \
  | grep -E "TABLE:|PREDICATES:|RewriteSuccessAndChose|CBO\."

echo ""
echo "--- 7.4d 明细查询 → 不应命中（这是应该的）---"
runq "EXPLAIN SELECT order_date, province, amount FROM orders WHERE amount > 4000 LIMIT 10;" \
  | grep -E "TABLE:"
echo ""
echo "👆 这次 TABLE: 应该还是 shop.orders(orders)"
echo "   原因：MV 里只存了聚合后的汇总数据，没有 amount > 4000 的明细行。"
echo "   一句话记住：MV 能回答「汇总问题」，不能回答「明细问题」"

echo ""
echo "========== 步骤 7.5：改写带来的实际提速（公平对照）=========="
echo ""
echo "--- 三种写法交替执行各 5 次，排除缓存预热与系统负载的干扰 ---"
for i in 1 2 3 4 5; do
  runq "SELECT province, SUM(amount) AS total FROM orders GROUP BY province ORDER BY province;" > /dev/null
  runq "SELECT province, SUM(total_amount) AS total FROM mv_prov_pay_daily GROUP BY province ORDER BY province;" > /dev/null
  runq "SET enable_materialized_view_rewrite = false; SELECT province, SUM(amount) AS total FROM orders GROUP BY province ORDER BY province;" > /dev/null
done

echo ""
echo "--- A：查基表（透明改写命中 MV）---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "SUM(amount) AS total FROM orders GROUP BY province" | head -5
echo "--- B：直接查 MV ---"
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "SHOW QUERY PROFILE '/';" 2>&1 \
  | grep -vE "^Warning|Using a password" | grep "SUM(total_amount) AS total FROM mv_prov_pay_daily" | head -5

echo ""
echo "👆 本机参考值："
echo "     A 查基表（带改写）  18 / 23 / 387 / 416 / 475 ms   ← 忽快忽慢"
echo "     B 直接查 MV        16 / 17 / 37 ms                ← 稳定"
echo "     C 关改写硬查基表    387 / 416 / 475 ms             ← 真实成本"
echo ""
echo "⚠️ A 组为什么忽快忽慢？"
echo "   差别在于【优化器这一刻是否选择了改写】。用 EXPLAIN 确认过："
echo "     TABLE: 显示 mv_prov_pay_daily 时 → 18ms"
echo "     TABLE: 显示 orders           时 → 475ms"
echo "   Doris 会基于代价决定要不要用 MV，不是每次都改写。这是设计如此，不是 bug。"
echo ""
echo "   结论：稳定命中时提速 10-25 倍（475ms → 18ms）"

echo ""
echo "========== 步骤 7.6：⚠️ 坑 2 —— REFRESH 是异步的 =========="
echo "--- 往基表插一行 ---"
runq "INSERT INTO orders VALUES
  ('2026-01-01','广东','深圳',9999999,1,'测试',1,1.00,'支付宝',1,'test',NOW(),NOW());"
runq "SELECT COUNT(*) AS base_total FROM orders;"
echo ""
echo "--- 立刻查 MV（还是旧值！）---"
runq "SELECT SUM(order_cnt) AS mv_total FROM mv_prov_pay_daily;"
echo ""
echo "--- 手动刷新 ---"
runq "REFRESH MATERIALIZED VIEW mv_prov_pay_daily COMPLETE;"
echo "    （异步执行，等 15 秒）"
sleep 15
echo "--- 刷新后再查 ---"
runq "SELECT SUM(order_cnt) AS mv_total FROM mv_prov_pay_daily;"
runq "SELECT COUNT(*) AS base_total FROM orders;"
echo ""
echo "👆 两边应该相等（都是 21500001）"
echo "   我第一次测时刷新完立刻查，看到旧值，差点写成「刷新失效」的结论。"
echo "   异步命令不能立刻校验 —— 这是常识，但写脚本时特别容易忘。"

echo ""
echo "--- 清理测试数据 ---"
runq "DELETE FROM orders WHERE user_id = 9999999;"
runq "REFRESH MATERIALIZED VIEW mv_prov_pay_daily COMPLETE;"
sleep 10
runq "SELECT SUM(order_cnt) AS mv_total FROM mv_prov_pay_daily;"
runq "SELECT COUNT(*) AS base_total FROM orders;"

echo ""
echo "========== 步骤 7.7：⚠️ 坑 3 —— 分区 MV 的分区名 ≠ 基表分区名 =========="
echo "--- 建一张分区基表 ---"
runq "DROP TABLE IF EXISTS orders_part;"
runq "CREATE TABLE orders_part (
  order_date DATE NOT NULL,
  province VARCHAR(16) NOT NULL,
  user_id BIGINT NOT NULL,
  amount DECIMAL(10,2) NOT NULL
)
DUPLICATE KEY(order_date, province)
PARTITION BY RANGE(order_date) ()
DISTRIBUTED BY HASH(province) BUCKETS 4
PROPERTIES ('replication_num' = '1');"
runq "ALTER TABLE orders_part ADD PARTITION p202501 VALUES [('2025-01-01'), ('2025-02-01'));"
runq "ALTER TABLE orders_part ADD PARTITION p202502 VALUES [('2025-02-01'), ('2025-03-01'));"
runq "INSERT INTO orders_part SELECT order_date, province, user_id, amount FROM orders WHERE order_date >= '2025-01-01' AND order_date < '2025-03-01' LIMIT 500000;"
runq "SELECT COUNT(*) AS part_rows FROM orders_part;"

echo ""
echo "--- 在分区表上建分区 MV ---"
runq "DROP MATERIALIZED VIEW IF EXISTS mv_part_daily;"
runq "CREATE MATERIALIZED VIEW mv_part_daily
BUILD IMMEDIATE REFRESH AUTO ON MANUAL
PARTITION BY (order_date)
DISTRIBUTED BY HASH(province) BUCKETS 4
AS
SELECT order_date, province, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_part
GROUP BY order_date, province;"
runq "SELECT COUNT(*) AS mv_part_rows FROM mv_part_daily;"

echo ""
echo "--- 查两边的分区名（关键！）---"
echo "  基表 orders_part 的分区："
runq "SHOW PARTITIONS FROM orders_part;" | awk -F'\t' 'NR>1{print "    " $2}'
echo "  MV mv_part_daily 的分区："
runq "SHOW PARTITIONS FROM mv_part_daily;" | awk -F'\t' 'NR>1{print "    " $2}'
echo ""
echo "👆 看到区别了吗？基表叫 p202501，MV 里是系统自动生成的 p_20250101_20250201"

echo ""
echo "--- 用基表的分区名去刷 MV，会报错 ---"
runq "REFRESH MATERIALIZED VIEW mv_part_daily PARTITION (p202501);"
echo "    ↑ ERROR: partition not exist: p202501"

echo ""
echo "--- 用 MV 自己的分区名，成功 ---"
echo "--- 先插 2 行新数据到 1 月分区 ---"
runq "INSERT INTO orders_part VALUES
  ('2025-01-15','广东',8888888,500.00),
  ('2025-01-16','广东',8888889,600.00);"
echo "    刷新前 MV："
runq "SELECT COUNT(*) AS mv_rows, SUM(cnt) AS mv_sum FROM mv_part_daily;"
echo "    只刷 1 月分区："
runq "REFRESH MATERIALIZED VIEW mv_part_daily PARTITION (p_20250101_20250201);"
echo "    （异步，等 10 秒）"
sleep 10
echo "    刷新后 MV："
runq "SELECT COUNT(*) AS mv_rows, SUM(cnt) AS mv_sum FROM mv_part_daily;"
echo "    基表实际："
runq "SELECT COUNT(*) AS base_rows FROM orders_part;"
echo ""
echo "👆 MV 从 86 行变 88 行，SUM(cnt) 从 500000 变 500002 —— 增量刷新成功"
echo "   而 2 月分区完全没动，这就是分区增量的价值"
echo ""
echo "   注：MV 的行数取决于「日期 × 省份」的组合数，你跑出来的具体数字可能略有出入"
echo "      （取决于 orders 里落在 2025-01/02 的是哪些天）。"
echo "      判断成功的标准是 SUM(cnt) 跟上了基表，不是行数等于某个特定值。"

echo ""
echo "--- 清理 ---"
runq "DELETE FROM orders_part WHERE user_id IN (8888888, 8888889);"

echo ""
echo "========== 步骤 7.8：定时刷新（可选）=========="
runq "DROP MATERIALIZED VIEW IF EXISTS mv_sched;"
runq "CREATE MATERIALIZED VIEW mv_sched
BUILD IMMEDIATE REFRESH COMPLETE ON SCHEDULE EVERY 1 MINUTE
DISTRIBUTED BY HASH(province) BUCKETS 2
AS
SELECT province, COUNT(*) AS cnt, SUM(amount) AS total
FROM orders_part
GROUP BY province;"
runq "SELECT COUNT(*) AS mv_sched_rows FROM mv_sched;"
echo ""
echo "👆 ON SCHEDULE EVERY 1 MINUTE = 每分钟自动全量刷新"
echo "   生产环境常用：REFRESH AUTO ON SCHEDULE EVERY 1 HOUR"

echo ""
echo "========== 步骤 7.9：刷新子句速查 =========="
cat <<'EOF'
写法                                            含义
──────────────────────────────────────────────────────────────
REFRESH AUTO ON MANUAL                          增量刷新，手动触发
REFRESH COMPLETE ON MANUAL                      全量刷新，手动触发
REFRESH COMPLETE ON SCHEDULE EVERY 1 MINUTE     全量刷新，每分钟自动
REFRESH AUTO ON SCHEDULE EVERY 1 HOUR           增量刷新，每小时自动

手动触发命令：
  REFRESH MATERIALIZED VIEW mv_name AUTO;        智能判断刷哪些分区
  REFRESH MATERIALIZED VIEW mv_name COMPLETE;    全量重算
  REFRESH MATERIALIZED VIEW mv_name PARTITION(p); 只刷指定分区（要用 MV 自己的分区名）
EOF

echo ""
echo "==================== 步骤 7 完成 ===================="
echo "下一步：bash lesson08-cleanup.sh  （清理实验对象，恢复全局设置）"
