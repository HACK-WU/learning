#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 3：Runtime Filter（Join 执行时才生成的过滤条件）
#
# 前提：已跑过 lesson08-setup.sh
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 3.1：默认开启时，RF 长什么样 =========="
echo ""
echo "SQL：查华南地区的订单，按省和大区汇总"
echo ""
runq "EXPLAIN SELECT o.province, d.region, COUNT(*) AS cnt, SUM(o.amount) AS amt
FROM fact_1m o JOIN dim_region d ON o.province = d.province
WHERE d.region = '华南'
GROUP BY o.province, d.region;"

echo ""
echo "👆 重点看这两行（一个 <- 一个 ->，成对出现）："
echo ""
echo "   |  runtime filters: RF000[min_max] <- province[#3](...), RF001[in_or_bloom] <- province[#3](...)"
echo "      TABLE: shop.fact_1m(fact_1m)"
echo "      runtime filters: RF000[min_max] -> province[#5], RF001[in_or_bloom] -> province[#5]"
echo ""
echo "   读法："
echo "     <-  从哪来：扫描右表 dim_region 时，把 province 的取值范围记下来"
echo "     ->  用到哪：把这个范围推给左表 fact_1m 的扫描算子，提前扔掉不可能匹配的行"

echo ""
echo "========== 步骤 3.2：关掉 RF，同一条 SQL 再看 =========="
echo ""
runq "SET runtime_filter_mode = OFF;
EXPLAIN SELECT o.province, d.region, COUNT(*) AS cnt, SUM(o.amount) AS amt
FROM fact_1m o JOIN dim_region d ON o.province = d.province
WHERE d.region = '华南'
GROUP BY o.province, d.region;"

echo ""
echo "👆 runtime filters 那两行【彻底消失】了。对比非常明显。"

echo ""
echo "========== 步骤 3.3：两种过滤器分别是什么 =========="
cat <<'EOF'
RF000[min_max]      最小值 / 最大值过滤器
                    记录右表该列的取值范围，左表扫描时只保留落在区间内的行
                    适合有序数据（日期、ID、金额）

RF001[in_or_bloom]  布隆过滤器
                    精确判断"某个值在不在集合里"，内存占用极小
                    适合离散值（省份、状态码、类型）
EOF

echo ""
echo "========== 步骤 3.4：相关变量（本机默认值）=========="
runq "SHOW VARIABLES LIKE 'runtime_filter%';"

echo ""
echo "========== 步骤 3.5：为什么叫'运行时'过滤 =========="
cat <<'EOF'
因为它在 SQL 编译阶段【根本不存在】。

编译期能知道的：表结构、分区信息、你写的 WHERE 条件
编译期不知道的：右表 dim_region 里到底有哪些 province

只有真正扫完右表，才能知道"华南对应广东、广西、福建这三个省"，
然后才能把"只要这三个省"这个条件推给左表。

这个"先扫右表、再过滤左表"的动作发生在【执行期】，
所以叫 Runtime Filter（运行时过滤器）。
这是编译器做不到的优化。
EOF

echo ""
echo "==================== 步骤 3 完成 ===================="
echo "下一步：bash lesson08-step4.sh  （VARIANT vs JSON 字符串）"
