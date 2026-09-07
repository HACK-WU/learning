#!/bin/bash
echo "=== 1. 重建 renderer（带 AUTH_TOKEN）==="
docker rm -f l12-renderer >/dev/null 2>&1
docker run -d --name l12-renderer --network l12net -p 8082:8081 \
  -e HTTP_PORT=8081 \
  -e AUTH_TOKEN=l12secrettoken123 \
  grafana/grafana-image-renderer:latest 2>&1 | tail -1
sleep 15
echo "  状态: $(docker ps -a --filter name=l12-renderer --format '{{.Status}}')"
docker network connect grafana-net l12-renderer 2>&1 | tail -1
echo

echo "=== 2. 重建 gf-render（保证在 l12net + grafana-net）==="
docker rm -f gf-render >/dev/null 2>&1
docker run -d --name gf-render --network l12net -p 3006:3000 \
  -e GF_RENDERING_SERVER_URL=http://l12-renderer:8081/render \
  -e GF_RENDERING_CALLBACK_URL=http://gf-render:3000/ \
  -e GF_RENDERING_RENDERER_TOKEN=l12secrettoken123 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:13.2.1 2>&1 | tail -1
docker network connect grafana-net gf-render 2>&1 | tail -1
for i in $(seq 1 60); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3006/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo

echo "=== 3. 配数据源 + 建 dashboard ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3006/api/datasources -H 'Content-Type: application/json' -d '{"name":"PromLab","type":"prometheus","url":"http://grafana-prom:9090","access":"proxy","uid":"promlab","isDefault":true}' -o /dev/null -w '  ds=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3006/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"rnd1","title":"Render Test","panels":[{"id":1,"type":"timeseries","title":"p1","gridPos":{"x":0,"y":0,"w":24,"h":8},"targets":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up"}]}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w '  dash=%{http_code}\n'
echo

echo "=== 4. API 查询 vs 渲染 PNG（各 3 次）==="
for i in 1 2 3; do
  T=$(curl -s --noproxy '*' -u admin:admin -o /dev/null -w '%{time_total}' -m 20 -X POST http://localhost:3006/api/ds/query -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up","instant":true}],"from":"now-1h","to":"now"}')
  echo "  API查询 第${i}次: ${T}s"
done
for i in 1 2 3; do
  R=$(curl -s --noproxy '*' -u admin:admin -o /tmp/rr_$i.png -w '%{time_total}|%{size_download}|%{http_code}' -m 120 'http://localhost:3006/render/dashboard-solo/db/rnd1?panelId=1&width=1000&height=500')
  echo "  渲染PNG 第${i}次: $R  (耗时|字节|码)"
done
echo
echo "  --- 确认 PNG 魔数 ---"
head -c 8 /tmp/rr_1.png | od -An -tx1 2>&1
ls -la /tmp/rr_1.png 2>&1
echo

echo "=== 5. 渲染并发 5 张 ==="
S=$(date +%s.%N)
for i in 1 2 3 4 5; do
  curl -s --noproxy '*' -u admin:admin -o /tmp/rc2_$i.png -w "  并发第${i}张: %{time_total}s  %{size_download}B  %{http_code}\n" -m 120 'http://localhost:3006/render/dashboard-solo/db/rnd1?panelId=1&width=1000&height=500' &
done
wait
E=$(date +%s.%N)
echo "  5 张并发总耗时=$(echo "$E - $S" | bc) 秒"
