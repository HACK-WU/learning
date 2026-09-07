#!/bin/bash
echo "=== 1. 起 image renderer ==="
docker rm -f l12-renderer >/dev/null 2>&1
docker network connect l12net grafana-lab 2>&1 | tail -1
docker run -d --name l12-renderer --network l12net -p 8081:8081 grafana/grafana-image-renderer:latest 2>&1 | tail -1
sleep 12
curl -s --noproxy '*' -m 8 http://localhost:8081/ -o /dev/null -w '  renderer_http=%{http_code}\n'
echo

echo "=== 2. 让 grafana-lab 知道 renderer 在哪（环境变量方式需重启，先看默认配置）==="
docker exec grafana-lab sh -c 'grep -A8 "^\[rendering\]" /etc/grafana/grafana.ini | head -12' 2>&1
echo

echo "=== 3. 不带 renderer 时渲染会怎样（现状）==="
curl -s --noproxy '*' -u admin:admin -m 25 -o /tmp/render1.png -w '  render_without_plugin=%{http_code} time=%{time_total}s size=%{size_download}\n' 'http://localhost:3001/render/dashboard-solo/db/perf-n1?panelId=1&width=1000&height=500' 2>&1
echo "  --- 返回内容前 200 字节 ---"
head -c 200 /tmp/render1.png 2>&1
echo
echo

echo "=== 4. 起一个带 renderer 的 Grafana（3006）==="
docker rm -f gf-render >/dev/null 2>&1
docker run -d --name gf-render --network l12net -p 3006:3000 \
  -e GF_RENDERING_SERVER_URL=http://l12-renderer:8081/render \
  -e GF_RENDERING_CALLBACK_URL=http://gf-render:3000/ \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  -e GF_INSTALL_PLUGINS= \
  grafana/grafana:13.2.1 2>&1 | tail -1
for i in $(seq 1 60); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3006/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo

echo "=== 5. 配数据源并建 dashboard 后测渲染 ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3006/api/datasources -H 'Content-Type: application/json' -d '{"name":"PromLab","type":"prometheus","url":"http://grafana-prom:9090","access":"proxy","uid":"promlab","isDefault":true}' -o /dev/null -w '  ds_create=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3006/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"rnd1","title":"Render Test","panels":[{"id":1,"type":"timeseries","title":"p1","gridPos":{"x":0,"y":0,"w":24,"h":8},"targets":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up"}]}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w '  dash_create=%{http_code}\n'
echo

echo "=== 6. 纯 API 查询 vs 渲染成 PNG 的耗时对比 ==="
T_API=$(curl -s --noproxy '*' -u admin:admin -o /dev/null -w '%{time_total}' -X POST http://localhost:3006/api/ds/query -H 'Content-Type: application/json' -d '{"queries":[{"refId":"A","datasource":{"uid":"promlab"},"expr":"up","instant":true}],"from":"now-1h","to":"now"}')
echo "  纯 API 查询: ${T_API}s"
T_RND=$(curl -s --noproxy '*' -u admin:admin -o /tmp/r2.png -w '%{time_total}|%{size_download}' -m 60 'http://localhost:3006/render/dashboard-solo/db/rnd1?panelId=1&width=1000&height=500')
echo "  渲染 PNG:    ${T_RND}  (格式: 耗时|字节)"
echo "  --- 是否真的是 PNG ---"
file /tmp/r2.png 2>&1
head -c 60 /tmp/r2.png | od -c 2>&1 | head -3
