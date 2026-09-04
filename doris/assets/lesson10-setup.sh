#!/bin/bash
# 课 10 步骤 0：创建实验用的 Workload Group 并授权
# 用法：bash lesson10-setup.sh
#
# 前置条件：
#   - doris-learn 容器在跑（docker ps 能看到 healthy）
#   - 课 9 已经拉起第二个 BE（1 FE + 2 BE），但本课不强制要求 2 个 BE
#   - shop 库里有 orders 表（2150 万行，课 1-7 建的）

FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 0. 环境检查 ====="
if ! docker ps --format '{{.Names}}' | grep -q '^doris-learn$'; then
  echo "  [FAIL] doris-learn 容器没在跑，请先启动"
  exit 1
fi
echo "  [OK] 容器在跑"

CNT=$($FE -e "SHOW BACKENDS\G" 2>&1 | grep -vE "^Warning|Using a password" | grep -c "Alive: true")
echo "  [INFO] Alive 的 BE 数量: $CNT"

# 检查 orders 表存在
if ! $FE -e "DESC orders;" 2>&1 | grep -q "user_id"; then
  echo "  [FAIL] orders 表不存在或没有 user_id 列，请先跑前面几课的建表脚本"
  exit 1
fi
echo "  [OK] orders 表存在"

# 检查 enable_sql_cache（测性能应该关掉）
SC=$($FE -e "SHOW VARIABLES LIKE 'enable_sql_cache';" 2>&1 | grep -vE "^Warning|Using a password" | awk 'NR==2{print $2}')
echo "  [INFO] enable_sql_cache = $SC （测性能应为 false；若是 true，第二次查询会走缓存，耗时不准）"

echo ""
echo "===== 1. 清理可能残留的实验组 ====="
for g in big_etl fast_report wg_c1 wg_c5; do
  out=$(q "DROP WORKLOAD GROUP IF EXISTS $g;" 2>&1)
  if [ -n "$out" ]; then
    echo "  已删: $g"
  fi
done

# 防止组数超过 15（硬限制）
NUM=$(q "SHOW WORKLOAD GROUPS;" | grep -vE "^Warning|Using a password" | tail -n +2 | wc -l)
echo "  当前组数: $NUM （上限 15）"
if [ "$NUM" -gt 10 ]; then
  echo "  [WARN] 组数偏多，可能触碰 15 的上限"
fi

echo ""
echo "===== 2. 创建实验组 ====="

# big_etl：大查询组，限并发 1，允许排队
q "CREATE WORKLOAD GROUP IF NOT EXISTS big_etl PROPERTIES (
     'min_memory_percent'    = '5',
     'max_memory_percent'    = '30',
     'max_concurrency'       = '1',
     'max_queue_size'        = '3',
     'queue_timeout'         = '30000'
   );" >/dev/null 2>&1
if $FE -e "SHOW WORKLOAD GROUPS;" 2>&1 | grep -q "big_etl"; then
  echo "  [OK] big_etl 创建成功（并发上限 1，队列 3）"
else
  echo "  [FAIL] big_etl 创建失败"
fi

# fast_report：报表组，并发高，不排队
q "CREATE WORKLOAD GROUP IF NOT EXISTS fast_report PROPERTIES (
     'min_memory_percent'    = '5',
     'max_memory_percent'    = '30',
     'max_concurrency'       = '10',
     'max_queue_size'        = '0',
     'queue_timeout'         = '0'
   );" >/dev/null 2>&1
if $FE -e "SHOW WORKLOAD GROUPS;" 2>&1 | grep -q "fast_report"; then
  echo "  [OK] fast_report 创建成功（并发上限 10，不排队）"
else
  echo "  [FAIL] fast_report 创建失败"
fi

# wg_c1：拒绝策略（并发 1，队列 0）
q "CREATE WORKLOAD GROUP IF NOT EXISTS wg_c1 PROPERTIES (
     'max_concurrency'       = '1',
     'max_queue_size'        = '0',
     'queue_timeout'         = '0'
   );" >/dev/null 2>&1
if $FE -e "SHOW WORKLOAD GROUPS;" 2>&1 | grep -q "wg_c1"; then
  echo "  [OK] wg_c1 创建成功（并发上限 1，队列 0 —— 拒绝策略）"
else
  echo "  [FAIL] wg_c1 创建失败"
fi

# wg_c5：排队策略（并发 1，队列 5，超时 10 秒）
q "CREATE WORKLOAD GROUP IF NOT EXISTS wg_c5 PROPERTIES (
     'max_concurrency'       = '1',
     'max_queue_size'        = '5',
     'queue_timeout'         = '10000'
   );" >/dev/null 2>&1
if $FE -e "SHOW WORKLOAD GROUPS;" 2>&1 | grep -q "wg_c5"; then
  echo "  [OK] wg_c5 创建成功（并发上限 1，队列 5 —— 排队策略）"
else
  echo "  [FAIL] wg_c5 创建失败"
fi

echo ""
echo "===== 3. 授权给 root（必须做，否则 SET PROPERTY 绑不上）====="
for g in big_etl fast_report wg_c1 wg_c5; do
  err=$(q "GRANT USAGE_PRIV ON WORKLOAD GROUP '$g' TO root;" 2>&1)
  if [ -z "$err" ]; then
    echo "  [OK] $g 已授权"
  else
    echo "  [FAIL] $g 授权失败: $err"
  fi
done

echo ""
echo "===== 4. 恢复 root 默认组为 normal（避免影响后续步骤）====="
q "SET PROPERTY FOR 'root' 'default_workload_group' = 'normal';" >/dev/null 2>&1
echo "  当前绑定："
q "SHOW PROPERTY FOR 'root' LIKE '%workload%';" | sed 's/^/    /'

echo ""
echo "===== 5. 当前组列表 ====="
q "SHOW WORKLOAD GROUPS;" | cut -f2 | sed 's/^/  /'

echo ""
echo "===== 6. 确认 enable_spill 当前状态（默认 false）====="
q "SHOW VARIABLES LIKE 'enable_spill';" | sed 's/^/  /'

echo ""
echo "===== setup 完成 ====="
echo "  下一步：bash lesson10-step1.sh （验证资源隔离）"
