#!/bin/bash
echo "=== 1. inotify 限制现状 ==="
cat /proc/sys/fs/inotify/max_user_instances 2>&1
cat /proc/sys/fs/inotify/max_user_watches 2>&1
echo

echo "=== 2. 尝试在容器内调高（需要 privileged）==="
docker rm -f p3-promtail >/dev/null 2>&1
docker run -d --name p3-promtail --network grafana-net --privileged \
  -v "/mnt/d/projects/learning/grafana/projects/从告警到定位/实现/promtail/promtail.yml:/etc/promtail/promtail.yml:ro" \
  -v "/mnt/d/projects/learning/grafana/projects/从告警到定位/实现/app/logs:/var/log/shop:ro" \
  grafana/promtail:3.0.0 \
  -config.file=/etc/promtail/promtail.yml 2>&1 | tail -2
sleep 6
echo "  状态: $(docker ps -a --filter name=p3-promtail --format '{{.Status}}')"
docker logs p3-promtail 2>&1 | tail -6
echo

echo "=== 3. 方案 B：不用 promtail 的文件发现，改用 Docker 服务发现不行的话，"
echo "    直接让应用把日志【以 HTTP 方式推给 Loki】（绕开文件采集）==="
echo "    (先看看方案 A 是否成功，成功则跳过)"
if docker ps --filter name=p3-promtail --format '{{.Status}}' | grep -q Up; then
  echo "  ✅ Promtail 已运行，等日志进 Loki"
  sleep 25
  curl -s --noproxy '*' -m 10 -G 'http://localhost:3101/loki/api/v1/query_range' --data-urlencode 'query={job="shop"}' --data-urlencode 'limit=2' --data-urlencode "start=$(( $(date +%s) - 600 ))000000000" --data-urlencode "end=$(date +%s)000000000" 2>&1 | head -c 500
  echo
else
  echo "  ❌ Promtail 仍失败，改用方案 B：应用直推 Loki"
fi
