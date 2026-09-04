#!/bin/bash
# ============================================================
# 课 8 第四幕 步骤 6：Array / Map / Struct（schema 固定但值是复合的）
#
# 前提：无特殊依赖，本步骤独立可跑
# ============================================================
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"

runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}

echo "========== 步骤 6.1：建表 =========="
runq "DROP TABLE IF EXISTS user_profile;"
runq "CREATE TABLE user_profile (
  uid BIGINT NOT NULL,
  tags ARRAY<STRING> NULL,
  extra MAP<STRING,STRING> NULL,
  addr STRUCT<city:STRING,zip:STRING> NULL
)
DUPLICATE KEY(uid)
DISTRIBUTED BY HASH(uid) BUCKETS 2
PROPERTIES ('replication_num' = '1');"

echo ""
echo "========== 步骤 6.2：插入数据 =========="
echo "⚠️ 注意 STRUCT 要用 named_struct() 函数构造，不能直接写字面量"
runq "INSERT INTO user_profile VALUES
  (1001, ['vip','new'],       {'src':'app','ch':'a1'},  named_struct('city','深圳','zip','518000')),
  (1002, ['vip','old','big'], {'src':'web','ch':'b2'},  named_struct('city','北京','zip','100000')),
  (1003, ['new'],             {'src':'app','ch':'c3'},  named_struct('city','上海','zip','200000'));"

echo ""
echo "========== 步骤 6.3：查全部 =========="
runq "SELECT uid, tags, extra, addr FROM user_profile ORDER BY uid;"
echo ""
echo "👆 预期输出："
echo "   1001  [\"vip\", \"new\"]        {\"src\":\"app\", \"ch\":\"a1\"}   {\"city\":\"深圳\", \"zip\":\"518000\"}"
echo "   1002  [\"vip\", \"old\", \"big\"] {\"src\":\"web\", \"ch\":\"b2\"}   {\"city\":\"北京\", \"zip\":\"100000\"}"
echo "   1003  [\"new\"]               {\"src\":\"app\", \"ch\":\"c3\"}   {\"city\":\"上海\", \"zip\":\"200000\"}"

echo ""
echo "========== 步骤 6.4：⚠️ 数组下标从 1 开始 =========="
runq "SELECT uid, tags[0] AS idx0, tags[1] AS idx1, tags[2] AS idx2 FROM user_profile ORDER BY uid;"
echo ""
echo "👆 预期输出（注意 idx0 全是 NULL）："
echo "   1001  NULL  vip   new"
echo "   1002  NULL  vip   old"
echo "   1003  NULL  new   NULL"
echo ""
echo "   tags[0] 是 NULL，tags[1] 才是第一个元素！"
echo "   这和 C / Java / Python 的习惯完全相反，是从 SQL 标准继承来的。"
echo "   写错的表现是「查出来全是 NULL」，但【不报错】，所以特别隐蔽。"

echo ""
echo "========== 步骤 6.5：Map 取值 =========="
runq "SELECT uid, extra['src'] AS src, extra['ch'] AS ch FROM user_profile ORDER BY uid;"
echo ""
echo "👆 预期：1001 app a1 / 1002 web b2 / 1003 app c3"

echo ""
echo "========== 步骤 6.6：Struct 取字段（用点号）=========="
runq "SELECT uid, addr.city AS city, addr.zip AS zip FROM user_profile ORDER BY uid;"
echo ""
echo "👆 预期：1001 深圳 518000 / 1002 北京 100000 / 1003 上海 200000"

echo ""
echo "========== 步骤 6.7：常用数组函数 =========="
echo "--- 数组长度 + 包含判断 ---"
runq "SELECT uid, size(tags) AS n, array_contains(tags,'vip') AS is_vip FROM user_profile ORDER BY uid;"
echo "👆 预期：1001 2 1 / 1002 3 1 / 1003 1 0"

echo ""
echo "--- 数组展开（行转列，最常用）---"
runq "SELECT uid, tag FROM user_profile LATERAL VIEW explode(tags) t AS tag ORDER BY uid, tag;"
echo "👆 预期：3 行变 6 行"
echo "   1001 new / 1001 vip / 1002 big / 1002 old / 1002 vip / 1003 new"

echo ""
echo "--- 数组聚合 ---"
runq "SELECT array_agg(DISTINCT extra['src']) AS all_src FROM user_profile;"
echo "👆 预期：[\"app\", \"web\"]"

echo ""
echo "========== 步骤 6.8：三种类型什么时候用 =========="
cat <<'EOF'
场景                              选型
─────────────────────────────────────────────────────
字段固定、数量少                   普通列（最快）
字段不固定 / 经常新增              VARIANT
字段固定，但值是列表（标签、路径）   ARRAY<T>
字段固定，但值是键值对（扩展属性）   MAP<K,V>
字段固定，值是已知的小结构（地址）   STRUCT<...>
已经存成 JSON 字符串了             迁到 VARIANT，收益 5-7 倍
EOF

echo ""
echo "==================== 步骤 6 完成 ===================="
echo "下一步：bash lesson08-step7.sh  （异步物化视图与透明改写）"
