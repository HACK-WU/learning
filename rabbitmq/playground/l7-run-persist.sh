#!/usr/bin/env bash
# 课 7 知识点 1 实测：三层持久化 + 容器重启对照
# 流程：构建三组 → docker restart → 等待就绪 → 检查三组存活情况
source "$(dirname "$0")/l7-env.sh"
set -u
cd "$(dirname "$0")"

echo "############ 阶段 1：构建三组对照 ############"
python l7-persist.py build 2>&1

echo ""
echo "############ 阶段 2：重启容器 ############"
"$DOCKER" restart "$RMQ_CT" >/dev/null 2>&1
echo "已发起 restart，等待 broker 就绪..."

for i in $(seq 1 60); do
  if "$DOCKER" exec "$RMQ_CT" rabbitmqctl status >/dev/null 2>&1; then
    echo "broker 已就绪（等待 ${i} 秒）"
    break
  fi
  sleep 1
done

# 再等几秒确保队列恢复完成
sleep 5

echo ""
echo "############ 阶段 3：检查重启后的存活情况 ############"
python l7-persist.py check 2>&1
