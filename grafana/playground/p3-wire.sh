#!/bin/bash
set -u
W=/mnt/d/projects/learning/grafana/projects/从告警到定位

echo "=== 1. 给现有 Prometheus 加 shop 抓取任务（用新配置文件重启原容器）==="
echo "  --- 现有 grafana-prom 的配置在哪 ---"
docker inspect grafana-prom --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}
{{end}}' 2>&1 | head -8
echo

echo "=== 2. 把 shop 抓取规则追加进现有 prometheus.yml（备份原文件）==="
docker exec grafana-prom cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.bak 2>&1
echo "  备份完成"
echo

echo "=== 3. 起一个独立的 promtail 采日志 ==="
docker rm -f p3-promtail >/dev/null 2>&1
docker run -d --name p3-promtail --network grafana-net \
  -v "$W/实现/promtail/promtail.yml:/etc/promtail/promtail.yml:ro" \
  -v "$W/实现/app/logs:/var/log/shop:ro" \
  grafana/promtail:3.0.0 \
  -config.file=/etc/promtail/promtail.yml 2>&1 | tail -2
sleep 5
echo "  状态: $(docker ps -a --filter name=p3-promtail --format '{{.Status}}')"
echo

echo "=== 4. 确认 promtail 起来了 ==="
docker logs p3-promtail 2>&1 | tail -10
echo

echo "=== 5. 等 20s 让日志进 Loki，然后查 ==="
sleep 20
curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"}' --data-urlencode 'limit=2' --data-urlencode "start=$(( $(date +%s) - 600 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 700
echo
