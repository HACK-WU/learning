#!/usr/bin/env bash
# 课 8 webhook 连通性验证：Grafana 容器能否访问宿主机 9999
set -u

echo "--- [1] 宿主机 9999 是否在监听 ---"
netstat -ano | grep ':9999' | head -5 | sed 's/^/  /'
echo "  (无输出=未监听)"

echo ""
echo "--- [2] 宿主机自测 ---"
curl -s -m 3 -o /dev/null -w '  localhost:9999 -> HTTP %{http_code}\n' http://localhost:9999/ || echo "  localhost:9999 不通"

echo ""
echo "--- [3] Grafana 容器网络 ---"
docker inspect grafana-lab --format '  NetworkMode={{.HostConfig.NetworkMode}}'
docker inspect grafana-lab --format '  Networks={{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'

echo ""
echo "--- [4] 容器内解析 host.docker.internal ---"
docker exec grafana-lab getent hosts host.docker.internal 2>&1 | sed 's/^/  /'
echo "  (无输出=无法解析)"

echo ""
echo "--- [5] 容器内访问宿主机 9999（三种写法）---"
for h in host.docker.internal 172.17.0.1 host.containers.internal; do
  code=$(docker exec grafana-lab sh -c "wget -q -O /dev/null -T 3 http://$h:9999/ 2>/dev/null; echo \$?")
  echo "  $h -> wget exit=$code"
done

echo ""
echo "--- [6] docker0 / bridge 网关 IP ---"
docker inspect grafana-lab --format '  Gateway={{.NetworkSettings.Gateway}}'
ip route 2>/dev/null | grep default | head -2 | sed 's/^/  /'

echo ""
echo "--- [7] 宿主机局域网 IP（WSL 场景）---"
hostname -I 2>/dev/null | sed 's/^/  /'

echo ""
echo "--- [8] 备选：把接收端跑在容器里（同网络）---"
docker ps --format '{{.Names}}' | grep -iE 'grafana' | sed 's/^/  已有容器: /'
