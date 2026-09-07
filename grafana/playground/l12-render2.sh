#!/bin/bash
echo "=== 1. 清理并用 8082 + 自定义 token 重建 ==="
docker rm -f l12-renderer gf-render >/dev/null 2>&1
docker run -d --name l12-renderer --network l12net -p 8082:8081 \
  -e HTTP_PORT=8081 \
  grafana/grafana-image-renderer:latest 2>&1 | tail -2
sleep 15
echo "  renderer 状态: $(docker ps -a --filter name=l12-renderer --format '{{.Status}}')"
curl -s --noproxy '*' -m 8 http://localhost:8082/ -o /dev/null -w '  health_http=%{http_code}\n'
echo

echo "=== 2. 起 gf-render（3006），带非默认 token ==="
docker run -d --name gf-render --network l12net -p 3006:3000 \
  -e GF_RENDERING_SERVER_URL=http://l12-renderer:8081/render \
  -e GF_RENDERING_CALLBACK_URL=http://gf-render:3000/ \
  -e GF_RENDERING_RENDERER_TOKEN=l12secrettoken123 \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:13.2.1 2>&1 | tail -1
for i in $(seq 1 60); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3006/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo "  gf-render 状态: $(docker ps -a --filter name=gf-render --format '{{.Status}}')"
echo

echo "=== 3. 配数据源 + 建 dashboard ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3006/api/datasources -H 'Content-Type: application/json' -d '{"name":"PromLab","type":"prometheus","url":"http://grafana-prom:9090","access":"proxy","uid":"promlab","isDefault":true}' -o /dev/null -w '  ds_create=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3006/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"rnd1","title":"Render Test","panels":[{"id":1,"type":"timeseries","title":"p1","gridPos":{"x":0,"y":0,"w":24,"h":8},"targets":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up"}]}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w '  dash_create=%{http_code}\n'
echo

echo "=== 4. 纯 API 查询 vs 渲染 PNG 耗时对比（各 3 次）==="
for i in 1 2 3; do
  T_API=$(curl -s --noproxy '*' -u admin:admin -o /dev/null -w '%{time_total}' -X POST http://localhost:3006/api/ds/query -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up","instant":true}],"from":"now-1h","to":"now"}')
  echo "  第${i}次 API查询: ${T_API}s"
done
for i in 1 2 3; do
  R=$(curl -s --noproxy '*' -u admin:admin -o /tmp/r_$i.png -w '%{time_total}|%{size_download}|%{http_code}' -m 90 'http://localhost:3006/render/dashboard-solo/db/rnd1?panelId=1&width=1000&height=500')
  echo "  第${i}次 渲染PNG: $R  (耗时|字节|状态码)"
done
echo
echo "  --- 确认是 PNG ---"
ls -la /tmp/r_1.png 2>&1
head -c 8 /tmp/r_1.png | od -An -tx1 2>&1
echo

echo "=== 5. 渲染并发：同时渲染 5 张 ==="
S=$(date +%s.%N)
for i in 1 2 3 4 5; do
  curl -s --noproxy '*' -u admin:admin -o /tmp/rc_$i.png -m 90 'http://localhost:3006/render/dashboard-solo/db/rnd1?panelId=1&width=1000&height=500' &
done
wait
E=$(date +%s.%N)
echo "  5 张并发渲染总耗时=$(echo "$E - $S" | bc) 秒"
ls -la /tmp/rc_*.png 2>&1 | head -6
