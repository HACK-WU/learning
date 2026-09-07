#!/bin/bash
echo "=== 1. renderer 启动失败的完整报错 ==="
docker logs l12-renderer 2>&1 | tail -15
echo
echo "=== 2. 容器状态 ==="
docker ps -a --filter name=l12-renderer --format '{{.Names}}\t{{.Status}}'
echo
echo "=== 3. 不带自定义参数直接起（看默认 CMD）==="
docker rm -f l12-renderer >/dev/null 2>&1
docker run -d --name l12-renderer --network l12net -p 8081:8081 grafana/grafana-image-renderer:latest 2>&1 | tail -3
sleep 15
docker ps -a --filter name=l12-renderer --format '  {{.Names}}\t{{.Status}}'
curl -s --noproxy '*' -m 8 http://localhost:8081/ -o /dev/null -w '  health_http=%{http_code}\n'
echo "  --- 日志 ---"
docker logs l12-renderer 2>&1 | tail -12
echo
echo "=== 4. gf-render 状态 ==="
docker ps -a --filter name=gf-render --format '  {{.Names}}\t{{.Status}}'
docker logs gf-render 2>&1 | tail -6
