#!/bin/bash
PG="docker exec l12-pg psql -U grafana -d grafana -tAc"
echo "########## 12.x 看不到 13.x 的 dashboard：根因定位 ##########"
echo

echo "=== 1. 13.x 的 dashboard 存在哪（resource 表）==="
echo "  --- resource 表内容 ---"
$PG "select \"group\", resource, namespace, name from resource limit 10;" 2>&1
echo

echo "=== 2. 传统 dashboard 表是空的吗 ==="
echo "  --- dashboard 表记录数 ---"
$PG "select count(*) from dashboard;" 2>&1
echo "  --- dashboard 表内容 ---"
$PG "select id, uid, title from dashboard limit 5;" 2>&1
echo

echo "=== 3. resource_history 里有没有 dashboard ==="
$PG "select \"group\", resource, namespace, name from resource_history limit 10;" 2>&1
echo

echo "=== 4. 对照组：12.0.0 自己建的 dashboard 存在哪 ==="
echo "  --- 在 gf-old(3007) 上建一个（如果它还在跑）---"
docker start gf-old >/dev/null 2>&1
sleep 20
curl -s --noproxy '*' -u admin:admin -X POST http://localhost:3007/api/dashboards/db -H 'Content-Type: application/json' -d '{"dashboard":{"uid":"old-created","title":"Created By 12.0.0","panels":[{"id":1,"type":"text","title":"t","gridPos":{"x":0,"y":0,"w":12,"h":8}}],"schemaVersion":41},"overwrite":true}' -o /dev/null -w '  create_on_12=%{http_code}\n'
echo "  --- 建完后 dashboard 表 ---"
$PG "select id, uid, title from dashboard limit 5;" 2>&1
echo "  --- 建完后 resource 表 ---"
$PG "select \"group\", resource, namespace, name from resource limit 10;" 2>&1
echo

echo "=== 5. 关键对照：12.0.0 建的，13.2.1 能看见吗 ==="
curl -s --noproxy '*' -u admin:admin http://localhost:3004/api/dashboards/uid/old-created -o /dev/null -w '  13.2.1 读 12.0.0 建的 old-created=%{http_code}\n'
echo

echo "=== 6. unified storage 开关（13.x 的核心变更）==="
docker exec gf-pg1 printenv | grep -Ei 'GF_UNIFIED|GF_STORAGE' || echo "  (无显式环境变量)"
docker exec gf-pg1 sh -c 'grep -Ei "^;?target|^;?\[unified_storage|^;?storage_type" /etc/grafana/grafana.ini 2>/dev/null | head -10' 2>&1
echo "  --- 13.2.1 启动日志里的 unified 提示 ---"
docker logs gf-pg1 2>&1 | grep -iE 'unified|storage_type' | head -5
