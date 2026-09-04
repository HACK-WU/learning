#!/bin/bash
# 课 11 评审 4：找 DROP SNAPSHOT 的正确语法
FE='docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot shop'
q() { $FE -e "$1" 2>&1 | grep -vE "^Warning|Using a password"; }

echo "===== 1. DROP SNAPSHOT 各种写法（看完整报错，不要截断）====="
echo "--- A: DROP SNAPSHOT <name> ON <repo> ---"
q "DROP SNAPSHOT tb_3 ON s3_repo;" 2>&1 | sed 's/^/  /'
echo "--- B: DROP SNAPSHOT ON <repo> WHERE SNAPSHOT = '<name>' ---"
q "DROP SNAPSHOT ON s3_repo WHERE SNAPSHOT = 'tb_3';" 2>&1 | sed 's/^/  /'
echo "--- C: DROP SNAPSHOT <db>.<name> ON <repo> ---"
q "DROP SNAPSHOT shop.tb_3 ON s3_repo;" 2>&1 | sed 's/^/  /'
echo "--- D: 只写快照名 ---"
q "DROP SNAPSHOT tb_3;" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 查 HELP ====="
q "HELP DROP SNAPSHOT;" 2>&1 | sed 's/^/  /'
q "HELP 'DROP';" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 看 FE 日志里的语法提示 ====="
docker exec doris-learn bash -c "grep -iE 'DROP SNAPSHOT' /opt/apache-doris/fe/log/fe.log 2>/dev/null | tail -5" | sed 's/^/  /'

echo ""
echo "===== 4. 换个思路：直接从 S3 删除快照目录 ====="
echo "--- MinIO 里的快照目录 ---"
docker exec doris-minio ls /data/doris-demo/backup11/__palo_repository_s3_repo/ 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 最实用的清理办法：删掉整个仓库 + 清 S3 目录 ====="
q "DROP REPOSITORY s3_repo;" 2>&1 | sed 's/^/  /'
q "SHOW REPOSITORIES;" | sed 's/^/  /'
echo "--- 删 S3 上的备份目录 ---"
docker exec doris-minio rm -rf /data/doris-demo/backup11/ 2>&1 | sed 's/^/  /'
docker exec doris-minio ls /data/doris-demo/ 2>&1 | sed 's/^/  /'
