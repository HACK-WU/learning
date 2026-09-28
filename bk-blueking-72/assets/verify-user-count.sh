#!/usr/bin/env bash
set -uo pipefail
NS=blueking
echo "===== bkrepo.user 现有全部用户（谁建的）====="
kubectl exec bk-mongodb-0 -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval '
db.getSiblingDB(\"bkrepo\").user.find({},{userId:1,name:1,admin:1,createdDate:1}).forEach(function(u){
  print(\"  userId=\"+u.userId+\"  name=\"+u.name+\"  admin=\"+u.admin+\"  created=\"+u.createdDate);
});
print(\"  total=\"+db.getSiblingDB(\"bkrepo\").user.count());
'" 2>&1

echo ""
echo "===== init-data.js 官方建了哪几个（从镜像里读）====="
kubectl get job bk-repo-bkrepo-init-mongodb -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/^/  image: /'
echo ""
echo "  (无法直接读已删 Job 的脚本，用 Job 日志里的输出推断)"
kubectl logs -n $NS -l job-name=bk-repo-bkrepo-init-mongodb --tail=20 2>&1 | sed 's/^/  /'
