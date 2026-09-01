#!/usr/bin/env bash
# 清理本轮 Phase 3 探测产生的临时队列与交换机
# 只删本轮亲手创建的 p3.* / drillb.* / chaos.* 前缀，不动其他
set -u

CT=${1:-rmq1}

echo "=== 清理前 p3/drillb/chaos 队列数 ==="
docker exec "$CT" rabbitmqctl list_queues name 2>/dev/null | grep -cE '^(p3\.|drillb\.|chaos\.)'

echo
echo "=== 逐个删除 ==="
docker exec "$CT" rabbitmqctl list_queues name 2>/dev/null \
  | grep -E '^(p3\.|drillb\.|chaos\.)' \
  | while read -r q; do
      [ -z "$q" ] && continue
      if docker exec "$CT" rabbitmqctl delete_queue "$q" >/dev/null 2>&1; then
        echo "  已删队列 $q"
      else
        echo "  删除失败 $q"
      fi
    done

echo
echo "=== 删除探测交换机 ==="
for ex in p3.probe.topic p3.probe.dlx p3.probe5.dlx drillb.dlx; do
  if docker exec "$CT" rabbitmqctl list_exchanges name 2>/dev/null | grep -qx "$ex"; then
    # rabbitmqctl 无 delete_exchange 子命令（课 4 实测），走 HTTP API
    code=$(curl -s -o /dev/null -w '%{http_code}' -u learn:learn123 -X DELETE \
      "http://localhost:15681/api/exchanges/%2F/$ex")
    echo "  $ex → HTTP $code"
  fi
done

echo
echo "=== 清理后剩余 ==="
docker exec "$CT" rabbitmqctl list_queues name 2>/dev/null | grep -E '^(p3\.|drillb\.|chaos\.)' | wc -l

echo
echo "=== 项目队列保留情况（不应被删）==="
docker exec "$CT" rabbitmqctl list_queues name messages 2>/dev/null | grep -E '^(order\.|notify\.)'
