#!/bin/bash
echo "=== 1. 在 pg1 上建一个 dashboard（作为一致性探针）==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3004/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"ha-probe","title":"HA Probe From PG1","panels":[{"type":"text","id":1,"title":"t","gridPos":{"x":0,"y":0,"w":12,"h":8}}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w '  create_http=%{http_code}\n'
echo

echo "=== 2. 起第二个 Grafana 实例共享同一 Postgres（3005）==="
docker rm -f gf-pg2 >/dev/null 2>&1
docker run -d --name gf-pg2 --network l12net -p 3005:3000 \
  -e GF_DATABASE_TYPE=postgres \
  -e GF_DATABASE_HOST=l12-pg:5432 \
  -e GF_DATABASE_NAME=grafana \
  -e GF_DATABASE_USER=grafana \
  -e GF_DATABASE_PASSWORD=grafana \
  -e GF_DATABASE_SSL_MODE=disable \
  -e GF_SECURITY_ADMIN_PASSWORD=admin \
  grafana/grafana:13.2.1 2>&1 | tail -1
for i in $(seq 1 60); do
  R=$(curl -s --noproxy '*' -m 3 http://localhost:3005/api/health | tr -d ' \n')
  if [ -n "$R" ]; then echo "  ${i}x2s: $R"; break; fi
  sleep 2
done
echo

echo "=== 3. 从 pg2 读 pg1 建的 dashboard ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3005/api/dashboards/uid/ha-probe -o /tmp/ha.json -w '  read_http=%{http_code}\n'
head -c 300 /tmp/ha.json
echo
echo

echo "=== 4. 在 pg2 上建第二个 dashboard，回 pg1 验证 ==="
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3005/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"ha-probe2","title":"HA Probe From PG2","panels":[{"type":"text","id":1,"title":"t2","gridPos":{"x":0,"y":0,"w":12,"h":8}}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w '  create_on_pg2=%{http_code}\n'
curl -s --noproxy '*' -u admin:admin http://localhost:3004/api/dashboards/uid/ha-probe2 -o /dev/null -w '  read_back_on_pg1=%{http_code}\n'
echo

echo "=== 5. 关键问题：会话是否共享？（pg1 登录的 cookie 拿去 pg2 用）==="
echo "  --- pg1 登录 ---"
curl -s --noproxy '*' -c /tmp/c1.txt -X POST http://localhost:3004/login -H 'Content-Type: application/json' -d '{"user":"admin","password":"admin"}' -o /dev/null -w '  pg1_login=%{http_code}\n'
echo "  --- 用 pg1 的 cookie 访问 pg2 ---"
curl -s --noproxy '*' -b /tmp/c1.txt http://localhost:3005/api/user -o /tmp/u2.json -w '  pg2_with_pg1_cookie=%{http_code}\n'
head -c 200 /tmp/u2.json
echo
echo

echo "=== 6. 关键问题：两个实例是否重复告警？（看 alertmanager/ruler 配置）==="
echo "  --- pg1 的 HA 相关设置 ---"
docker exec gf-pg1 printenv | grep -Ei 'GF_UNIFIED_ALERTING|GF_ALERTING' || echo "    (无相关环境变量，用默认值)"
echo "  --- pg1 查 high availability 设置 ---"
docker exec gf-pg1 sh -c 'grep -Ei "ha_|high_avail" /etc/grafana/grafana.ini 2>/dev/null | head -20' || echo "    (grafana.ini 中未找到)"
echo

echo "=== 7. 数据库锁：两实例同时启动时是否抢迁移锁 ==="
docker logs gf-pg2 2>&1 | grep -Ei 'lock|migrat' | head -8
