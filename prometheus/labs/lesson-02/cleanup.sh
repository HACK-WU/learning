set -x

echo "=== 只清理课2实验容器（不碰其他课程的容器） ==="
for c in app-order-1 app-order-2 app-payment-1 app-user-1 app-conflict prometheus-l2 \
         v-order-1 v-order-2 v-payment-1 v-user-1 v-conflict v-prom; do
  docker rm -f "$c" >/dev/null 2>&1 || true
done

docker network rm lesson01-net >/dev/null 2>&1 || true
docker network rm lesson02-net >/dev/null 2>&1 || true

sleep 2
echo "=== 剩余容器（应只剩其他课程的） ==="
docker ps -a --format '{{.Names}}' | sort
