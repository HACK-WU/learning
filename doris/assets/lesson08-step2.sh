#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 2：看懂四种 Join 策略的 EXPLAIN 标记
#
# 前提：已跑过 lesson08-setup.sh
#
# ⚠️ 本课最重要的方法论：
#    本机只有 1 个 BE，所有数据都在一台机器上，网络代价恒为 0，
#    所以四种策略的【耗时差异根本测不出来】。
#    改用 EXPLAIN 里 join op 这个【确定性字段】作为证据。
#    课 7 已验证这个方法有效。
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 2.1：BROADCAST（右表很小）=========="
echo ""
echo "场景：100 万行的 fact_1m，关联 8 行的 dim_region"
echo ""
runq "EXPLAIN SELECT o.province, d.region, COUNT(*) AS cnt
FROM fact_1m o JOIN dim_region d ON o.province = d.province
GROUP BY o.province, d.region;"
echo ""
echo "👆 找这一行：join op: INNER JOIN(BROADCAST)[]"
echo "   含义：把右表 dim_region 完整复制到每个 BE 节点"

echo ""
echo "========== 步骤 2.1b：同一个右表，换张更大的左表会怎样？=========="
echo ""
echo "右表还是 8 行的 dim_region，但左表从 fact_1m(100万) 换成 orders(2150万)。"
echo "guess 一下：还是 BROADCAST 吗？"
echo ""
runq "EXPLAIN SELECT o.order_date, d.region
FROM orders o JOIN dim_region d ON o.province = d.province;" 2>&1 | grep -E "join op|EXCHANGE ID|BUCKET_SHFFULE"
echo ""
echo "👆 实测：join op 变成了 INNER JOIN(BUCKET_SHUFFLE)[]，不是 BROADCAST！"
echo "   原因：orders 的分桶键也是 province，于是'右表够小可广播'和"
echo "        'Join 键命中左表分桶键可 Bucket Shuffle'两个条件同时成立，"
echo "        优化器按代价估算二选一。两者代价都很低，选哪个属于估算边界内的浮动。"
echo ""
echo "   结论：策略是优化器算出来的，不是 SQL 写出来的。别靠猜，看 join op。"

echo ""
echo "========== 步骤 2.2：BUCKET_SHUFFLE（Join 键 = 左表分桶键）=========="
echo ""
echo "场景：orders 的分桶键是 province（8 桶），Join 键也是 province，"
echo "      右表 perf_wide 有 200 万行（够大，不会走 BROADCAST）"
echo ""
runq "EXPLAIN SELECT o.order_date, w.province
FROM orders o JOIN perf_wide w ON o.province = w.province;"
echo ""
echo "👆 找这一行：join op: INNER JOIN(BUCKET_SHUFFLE)[]"
echo "   含义：左表不动，右表按左表的分桶规则发过去，只搬右表一份数据"

echo ""
echo "========== 步骤 2.3：PARTITIONED / Shuffle（无路可走时）=========="
echo ""
echo "场景：2150 万的 orders 关联 2050 万的 orders_dup，Join 键 user_id 不是分桶键"
echo ""
runq "EXPLAIN SELECT o.order_date, p.province
FROM orders o JOIN orders_dup p ON o.user_id = p.user_id;"
echo ""
echo "👆 找这一行：join op: INNER JOIN(PARTITIONED)[]"
echo "   还要看：计划里出现了【两组】VEXCHANGE —— 左右两边都要洗牌"
echo "   这是最贵的一种：两边全量数据都要搬"

echo ""
echo "========== 步骤 2.4：COLOCATE（零网络代价）=========="
echo ""
echo "场景：orders 和 fact_prov 在同一个 colocation group，同分桶键(province)、同 8 桶"
echo ""
echo "⚠️ 注意：这里用 orders 而不是 fact_1m，因为 Colocate Join 要求【两张表都在组里】。"
echo "   fact_1m 在步骤 1 里也加进了 prov_group，但优化器在它上面倾向选 BROADCAST。"
echo "   orders（2150万）+ fact_prov（200万）两侧都够大，COLOCATE 才稳定出现。"
echo ""
runq "EXPLAIN SELECT o.order_date, f.province
FROM orders o JOIN fact_prov f ON o.province = f.province;"
echo ""
echo "👆 找这一行：join op: INNER JOIN(COLOCATE[])[]"
echo "   关键特征：左右两边都是 VOlapScanNode，【中间没有 VEXCHANGE】"
echo "   没有 EXCHANGE = 没有网络传输 = 零网络代价"

echo ""
echo "========== 步骤 2.5：Colocate 的开关对照实验 =========="
echo ""
echo "--- 2.5a 先关掉 colocate 优化，同一条 SQL 再看 ---"
runq "SET disable_colocate_plan = true;
EXPLAIN SELECT o.order_date, f.province
FROM orders o JOIN fact_prov f ON o.province = f.province;" 2>&1 | grep -E "join op"

echo ""
echo "--- 2.5b 再开回来，同一条 SQL 再看 ---"
runq "SET disable_colocate_plan = false;
EXPLAIN SELECT o.order_date, f.province
FROM orders o JOIN fact_prov f ON o.province = f.province;" 2>&1 | grep -E "join op"

echo ""
echo "👆 一个变量，标记就变了 —— 这就是因果关系的证明"
echo ""
echo "⚠️ 注意这里的写法：SET 和 EXPLAIN 用分号连在同一个连接里！"
echo "   如果写成两条命令（两个 docker exec），SET 会在连接断开时丢失，"
echo "   你会看到'明明关了却没效果'的假象。这是我踩过的坑。"

echo ""
echo "========== 步骤 2.6：四条策略速查 =========="
cat <<'EOF'
┌──────────────────┬────────────────────────┬──────────────────────┐
│ EXPLAIN 标记      │ 含义                    │ 网络代价              │
├──────────────────┼────────────────────────┼──────────────────────┤
│ BROADCAST        │ 右表复制到每个节点       │ 右表 × 节点数         │
│ BUCKET_SHUFFLE   │ 只搬右表，按左表桶分布    │ 右表一份              │
│ PARTITIONED      │ 两边都按 Join 键重分布    │ 左右各一份（最贵）     │
│ COLOCATE[]       │ 同号桶本就在同一 BE      │ 零                    │
└──────────────────┴────────────────────────┴──────────────────────┘
EOF

echo ""
echo "==================== 步骤 2 完成 ===================="
echo "下一步：bash lesson08-step3.sh  （Runtime Filter）"
