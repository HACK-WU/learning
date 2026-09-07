#!/bin/bash
B=http://localhost:3002
J='python3 -m json.tool'

echo "=== 0. 确认 alice 当前 Org ==="
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/org" | $J
echo

echo "=== 1. 越权测试：alice 在 Org2 用 uid 直接读 Org1 的 dashboard ==="
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/dashboards/uid/prov-dash-001" -o /tmp/x1 -w '  http=%{http_code}\n'
head -c 300 /tmp/x1; echo
echo

echo "=== 2. 越权测试：alice 在 Org2 读 Org1 的数据源 by uid ==="
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/datasources/uid/provprom" -o /tmp/x2 -w '  http=%{http_code}\n'
head -c 300 /tmp/x2; echo
echo

echo "=== 3. alice 在 Org2 能否建 dashboard ==="
curl -s --noproxy '*' -u alice:pass-alice-123 -X POST "$B/api/dashboards/db" \
  -H 'Content-Type: application/json' \
  -d '{"dashboard":{"uid":"hack-001","title":"Hacked","panels":[]},"overwrite":false}' -o /tmp/x3 -w '  http=%{http_code}\n'
head -c 300 /tmp/x3; echo
echo

echo "=== 4. alice 在 Org2 能否建数据源（Viewer 应被拒）==="
curl -s --noproxy '*' -u alice:pass-alice-123 -X POST "$B/api/datasources" \
  -H 'Content-Type: application/json' \
  -d '{"name":"HackDS","type":"prometheus","url":"http://x:9090","access":"proxy"}' -o /tmp/x4 -w '  http=%{http_code}\n'
head -c 300 /tmp/x4; echo
echo

echo "=== 5. 切回 Org1，alice(Viewer) 读数据源 ==="
curl -s --noproxy '*' -u alice:pass-alice-123 -X POST "$B/api/user/using/1" -o /dev/null -w '  switch http=%{http_code}\n'
curl -s --noproxy '*' -u alice:pass-alice-123 "$B/api/datasources" -o /tmp/x5 -w '  http=%{http_code}\n'
head -c 300 /tmp/x5; echo
