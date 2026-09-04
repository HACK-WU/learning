#!/bin/bash
MYSQL="docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop"
runq() {
  echo "$1" | $MYSQL 2>&1 | grep -vE "^Warning|Using a password"
}
echo "=== SHOW TABLES ==="
runq "SHOW TABLES;"
echo ""
echo "=== colocation group ==="
runq "SHOW PROC '/colocation_group';"
echo ""
echo "=== global vars ==="
runq "SHOW GLOBAL VARIABLES LIKE 'enable_sql_cache';"
runq "SHOW GLOBAL VARIABLES LIKE 'enable_profile';"
runq "SHOW GLOBAL VARIABLES LIKE 'enable_materialized_view_rewrite';"
