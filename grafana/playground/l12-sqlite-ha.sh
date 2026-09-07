#!/bin/bash
echo "########## SQLite 的边界：并发写入会不会锁 ##########"
echo

echo "=== 1. grafana-lab 用的是 SQLite，并发写 dashboard 测试 ==="
echo "  后台同时发起 10 个建表请求"
S=$(date +%s.%N)
for i in $(seq 1 10); do
  curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3001/api/dashboards/db -H 'Content-Type: application/json' -d "{\"dashboard\":{\"uid\":\"sl-$i\",\"title\":\"SQLite Concurrency $i\",\"panels\":[{\"id\":1,\"type\":\"text\",\"title\":\"t\",\"gridPos\":{\"x\":0,\"y\":0,\"w\":12,\"h\":8}}],\"schemaVersion\":41},\"overwrite\":true}" -o /tmp/sl_$i.out -w "%{http_code}\n" &
done
wait
E=$(date +%s.%N)
echo "  10 个并发写总耗时=$(echo "$E - $S" | bc) 秒"
echo "  --- 结果分布 ---"
cat /tmp/sl_*.out 2>/dev/null | sort | uniq -c
echo "  --- 有没有 database is locked 错误 ---"
cat /tmp/sl_*.out 2>/dev/null | grep -i 'locked' || echo "    无 locked 错误"
docker logs grafana-lab 2>&1 | tail -30 | grep -iE 'locked|busy|retry' || echo "    日志无锁竞争"
echo

echo "=== 2. SQLite 数据库文件锁机制 ==="
docker exec grafana-lab ls -la /var/lib/grafana/grafana.db* 2>&1
echo

echo "=== 3. 关键：SQLite 下能起第二个实例吗（共享同一文件）==="
echo "  --- grafana-lab 的 grafana.db 在宿主机的位置 ---"
docker inspect grafana-lab --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>&1 | head -5
echo "  (若为空说明用的是容器内部卷，无法共享 —— 这正是 SQLite 不能 HA 的根本原因)"
echo

echo "########## HA 告警：两实例会重复告警吗 ##########"
echo

echo "=== 4. 在 pg1 上配一条告警规则 ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/folders -H 'Content-Type: application/json' -d '{"uid":"l12ha","title":"L12 HA"}' -o /dev/null -w '  folder=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/v1/provisioning/alert-rules -H 'Content-Type: application/json' -d '{"uid":"ha-rule-1","title":"HA Test Rule","folderUID":"l12ha","ruleGroup":"ha-group","orgId":1,"condition":"B","noDataState":"NoData","execErrState":"Error","for":"0s","isPaused":false,"data":[{"refId":"A","datasourceUid":"__expr__","model":{"type":"math","expression":"1"}},{"refId":"B","datasourceUid":"__expr__","model":{"type":"threshold","expression":"A","conditions":[{"type":"query","evaluator":{"type":"gt","params":[0]}}]}}]}' -o /tmp/rule.json -w '  rule=%{http_code}\n'
head -c 250 /tmp/rule.json
echo
echo

echo "=== 5. 等 90 秒看两个实例的告警状态（是否都触发）==="
sleep 90
echo "  --- pg1(3004) 告警状态 ---"
curl -s --noproxy '*' -u admin:admin 'http://localhost:3004/api/alertmanager/grafana/api/v2/alerts' 2>&1 | head -c 400
echo
echo "  --- pg2(3005) 告警状态 ---"
docker start gf-pg2 >/dev/null 2>&1
sleep 20
curl -s --noproxy '*' -u admin:admin 'http://localhost:3005/api/alertmanager/grafana/api/v2/alerts' 2>&1 | head -c 400
echo
echo

echo "=== 6. 从 /metrics 看告警计数（避免只看 API）==="
curl -s --noproxy '*' -u admin:admin http://localhost:3004/metrics 2>&1 | grep -iE 'grafana_alerting_alerts|alerting_active' | head -6
