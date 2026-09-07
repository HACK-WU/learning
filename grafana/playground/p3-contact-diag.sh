#!/bin/bash
echo "=== 1. 用 API 查联系人的完整结构（看 receivers 为何为空）==="
curl -s --noproxy '*' -u admin:admin http://localhost:3130/api/v1/provisioning/contact-points 2>&1 | python3 -m json.tool 2>&1 | head -40
echo

echo "=== 2. 试一下用 Grafana 内部 API 看 ==="
curl -s --noproxy '*' -u admin:admin 'http://localhost:3130/api/alertmanager/grafana/config/api/v1/alerts' 2>&1 | head -c 600
echo
echo

echo "=== 3. 检查 notify.yaml 是否被正确读取（看文件内容）==="
docker exec p3-grafana cat /etc/grafana/provisioning/alerting/notify.yaml 2>&1 | head -25
