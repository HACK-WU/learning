#!/usr/bin/env bash
set -uo pipefail
NS=blueking
IMG=hub.bktencent.com/blueking/bkrepo-init:v3.3.1-beta.1
URI='mongodb://bkrepo:bkrepo@bk-mongodb-headless:27017/bkrepo?replicaSet=rs0'

echo "===== 0. 执行前状态 ====="
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval 'print(\"  user=\"+db.getSiblingDB(\"bkrepo\").user.count()+\" role=\"+db.getSiblingDB(\"bkrepo\").role.count())'" 2>&1

echo ""
echo "===== 1. 备份当前（空）集合，防误操作 ====="
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval 'db.getSiblingDB(\"bkrepo\").user.find().forEach(function(d){printjson(d)})'" 2>&1 | sed 's/^/  /' | head -5
echo "  (空则无备份需要)"

echo ""
echo "===== 2. 按 chart 原始定义跑 init-mongodb Job ====="
kubectl delete job bk-repo-bkrepo-init-mongodb -n $NS --wait=false >/dev/null 2>&1
sleep 2
cat <<EOF | kubectl apply -f - 2>&1 | sed 's/^/  /'
apiVersion: batch/v1
kind: Job
metadata:
  name: bk-repo-bkrepo-init-mongodb
  namespace: $NS
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: init-mongodb
        image: $IMG
        imagePullPolicy: IfNotPresent
        command: ['/bin/sh','-c','/data/workspace/init-mongodb.sh']
        env:
        - name: BK_REPO_USERNAME
          value: "admin"
        - name: BK_REPO_PASSWORD
          value: "blueking"
        - name: BK_REPO_MONGODB_URI
          value: "$URI"
        - name: BK_REPO_BCS_ACCESSKEY
          value: "bk_bcs_app"
        - name: BK_REPO_BCS_SECRETKEY
          value: "377bc14c-4163-4a3d-aa51-2ffdcc8e0dd7"
        - name: BK_REPO_ACCESSKEY
          value: "18b61c9c-901b-4ea3-89c3-1f74be944b66"
        - name: BK_REPO_SECRETKEY
          value: "Us8ZGDXPqk86cwMukYABQqCZLAkM3K"
        - name: BK_REPO_ENABLE_MULTI_TENANT_MODE
          value: "false"
        - name: BK_REPO_ENABLE_MONGODB_TLS
          value: "false"
EOF

echo ""
echo "===== 3. 等 Job 完成（最多 120s）====="
for i in $(seq 1 40); do
  S=$(kubectl get job bk-repo-bkrepo-init-mongodb -n $NS -o jsonpath='{.status.conditions[0].type}' 2>/dev/null)
  [ "$S" = "Complete" ] && { echo "  ✅ Complete"; break; }
  [ "$S" = "Failed" ] && { echo "  ❌ Failed"; break; }
  sleep 3
done
kubectl get job bk-repo-bkrepo-init-mongodb -n $NS --no-headers 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. Job 日志 ====="
kubectl logs -n $NS -l job-name=bk-repo-bkrepo-init-mongodb --tail=30 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 验证：user/role 集合是否有数据 ====="
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval '
print(\"  user count=\"+db.getSiblingDB(\"bkrepo\").user.count());
print(\"  role count=\"+db.getSiblingDB(\"bkrepo\").role.count());
db.getSiblingDB(\"bkrepo\").user.find().limit(3).forEach(function(u){print(\"   user: \"+JSON.stringify(u).slice(0,220))});
'" 2>&1

echo ""
echo "===== 6. 验证：admin/blueking 能否登录 ====="
kubectl exec netprobe -n $NS -- bash -c "curl -s -o /dev/null -w '  bkrepo admin:blueking -> HTTP %{http_code}\n' --max-time 10 -u admin:blueking http://bkrepo.paas.example.com/repository/api/project/list" 2>&1
