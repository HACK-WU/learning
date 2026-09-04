#!/bin/bash
# 课 2：启动 Doris all-in-one 容器
# 镜像：apache/doris:all-in-one-4.1.3（FE + BE 在同一容器内，仅供本地学习）
set -e

echo "=== 清理同名旧容器（如有）==="
docker rm -f doris-learn >/dev/null 2>&1 || true

echo ""
echo "=== 启动容器 ==="
docker run -d \
  --name doris-learn \
  -p 9030:9030 \
  -p 8030:8030 \
  -p 8040:8040 \
  apache/doris:all-in-one-4.1.3

echo ""
echo "=== 等待 FE 就绪（最长 5 分钟）==="
for i in $(seq 1 60); do
  if docker exec doris-learn bash -c "mysql -h 127.0.0.1 -P 9030 -uroot -e 'SHOW DATABASES;'" >/dev/null 2>&1; then
    echo "FE 已就绪（第 ${i} 次探测，约 $((i*5)) 秒）"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "FE 启动超时，查看日志："
    docker logs doris-learn 2>&1 | tail -40
    exit 1
  fi
  sleep 5
done

echo ""
echo "=== 查看 FE 日志尾部 ==="
docker exec doris-learn bash -c "cat /opt/apache-doris/fe/log/fe.log 2>/dev/null | tail -15" || echo "(日志路径待确认)"

echo ""
echo "=== 查看 BE 日志尾部 ==="
docker exec doris-learn bash -c "cat /opt/apache-doris/be/log/be.INFO 2>/dev/null | tail -15" || echo "(日志路径待确认)"

echo ""
echo "=== 列出容器内进程 ==="
docker exec doris-learn bash -c "ps aux | grep -E 'DorisFE|DorisBE|java' | grep -v grep | awk '{print \$11, \$12}' | head -10"

echo ""
echo "START_DONE"
