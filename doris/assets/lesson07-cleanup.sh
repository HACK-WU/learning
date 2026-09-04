#!/bin/bash
# 课 7 清理脚本
runq() {
  docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop -e "$1" 2>&1 \
    | grep -vE "^Warning|Using a password"
}

echo "=== 1. 删实验表 ==="
runq "DROP TABLE IF EXISTS perf_wide;"
runq "DROP TABLE IF EXISTS perf_wide_big;"

echo "=== 2. 确认已删除 ==="
runq "SHOW TABLES;"

echo "=== 3. 恢复全局设置 ==="
runq "SET GLOBAL enable_sql_cache = true;"
runq "SET GLOBAL enable_profile = false;"
runq "SET GLOBAL parallel_pipeline_task_num = 0;"
runq "SELECT @@enable_sql_cache AS cache, @@enable_profile AS prof;"

echo "CLEANUP_DONE"
