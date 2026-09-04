#!/bin/bash
# 课 2：补测 3 —— 分桶倾斜现象 + Web UI 可达性 + FE 三角色说明素材
DORIS="docker exec doris-learn mysql -h 127.0.0.1 -P 9030 -uroot"

echo "=========== 分桶倾斜：8 个 tablet 的行数分布 ==========="
$DORIS --batch -e "USE shop; SHOW TABLETS FROM orders;" 2>/dev/null | grep -vE "^Warning|Using a password" | awk -F'\t' 'NR>1 {printf "Tablet %s : %s 行\n", $1, $11}'

echo ""
echo "=========== 各省行数（理解为什么倾斜）==========="
$DORIS -e "USE shop; SELECT province, COUNT(*) c FROM orders GROUP BY province ORDER BY c DESC;" 2>/dev/null | grep -vE "^Warning|Using a password"

echo ""
echo "=========== Web UI 可达性 ==========="
echo -n "FE Web UI (8030) HTTP 状态: "
docker exec doris-learn bash -c "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8030/" 2>/dev/null
echo ""
echo -n "BE Web UI (8040) HTTP 状态: "
docker exec doris-learn bash -c "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8040/" 2>/dev/null
echo ""

echo ""
echo "=========== 宿主机端口映射确认 ==========="
docker ps --filter name=doris-learn --format "{{.Names}} | {{.Ports}}"

echo ""
echo "=========== MySQL 协议兼容证据 ==========="
$DORIS -e "SELECT VERSION();" 2>/dev/null | grep -vE "^Warning|Using a password"
echo "--- 用标准 MySQL 客户端能连（上面所有查询都是用 mysql 客户端执行的）---"

echo ""
echo "=========== 资源占用 ==========="
docker stats --no-stream --format "{{.Name}} | MEM {{.MemUsage}} | CPU {{.CPUPerc}}" doris-learn doris-mysql-demo 2>/dev/null

echo ""
echo "BENCH3_DONE"
