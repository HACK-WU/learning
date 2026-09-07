#!/bin/bash
echo "=== 1. gf-render 渲染 500 的真实错误 ==="
docker logs gf-render 2>&1 | grep -iE 'render|error|fail' | tail -15
echo

echo "=== 2. renderer 侧日志 ==="
docker logs l12-renderer 2>&1 | tail -15
echo

echo "=== 3. gf-render 能连到 renderer 吗 ==="
docker exec gf-render sh -c 'wget -qO- --timeout=5 http://l12-renderer:8081/ 2>&1 | head -c 200' 2>&1
echo
echo

echo "=== 4. gf-render 能连到 prom 吗（API 8s 的原因）==="
docker exec gf-render sh -c 'wget -qO- --timeout=8 http://grafana-prom:9090/api/v1/query?query=up 2>&1 | head -c 150' 2>&1
echo
echo "  --- gf-render 在哪个网络 ---"
docker inspect gf-render --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
echo "  --- grafana-prom 在哪个网络 ---"
docker inspect grafana-prom --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}'
echo

echo "=== 5. 把 gf-render 接入 grafana-net ==="
docker network connect grafana-net gf-render 2>&1 | tail -1
docker network connect grafana-net l12-renderer 2>&1 | tail -1
sleep 3
docker exec gf-render sh -c 'wget -qO- --timeout=8 http://grafana-prom:9090/api/v1/query?query=up 2>&1 | head -c 150' 2>&1
echo
echo

echo "=== 6. 重测 API 查询 ==="
for i in 1 2 3; do
  T=$(curl -s --noproxy '*' -u admin:admin -o /dev/null -w '%{time_total}' -m 20 -X POST http://localhost:3006/api/ds/query -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up","instant":true}],"from":"now-1h","to":"now"}')
  echo "  第${i}次: ${T}s"
done
