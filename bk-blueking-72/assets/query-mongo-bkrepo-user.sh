#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. mongodb Pod ====="
MP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep -i 'mongodb' | grep Running | awk '{print $1}' | head -1)
echo "  Pod: $MP"

echo ""
echo "===== 2. mongosh 可用？ ====="
kubectl exec $MP -n $NS -- which mongosh mongo 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 列出所有库 ====="
kubectl exec $MP -n $NS -- bash -c "mongosh --quiet -u root -p blueking --authenticationDatabase admin --eval 'db.adminCommand({listDatabases:1}).databases.forEach(d=>print(d.name))'" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 4. bkrepo 相关的库与集合 ====="
kubectl exec $MP -n $NS -- bash -c "mongosh --quiet -u root -p blueking --authenticationDatabase admin --eval 'db.adminCommand({listDatabases:1}).databases.map(d=>d.name).filter(n=>/repo|auth/i.test(n)).forEach(n=>{print(\"DB: \"+n); db.getSiblingDB(n).getCollectionNames().forEach(c=>print(\"   \"+c))})'" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 5. 查 user 集合内容（bkrepo 用户表）====="
kubectl exec $MP -n $NS -- bash -c "mongosh --quiet -u root -p blueking --authenticationDatabase admin --eval '
db.adminCommand({listDatabases:1}).databases.map(d=>d.name).forEach(function(n){
  var dbx=db.getSiblingDB(n);
  dbx.getCollectionNames().filter(function(c){return /user|account|account/i.test(c)}).forEach(function(c){
    print(\"=== \"+n+\".\"+c+\" ===\");
    dbx.getCollection(c).find({},{password:1,userId:1,name:1,type:1}).limit(10).forEach(function(u){print(JSON.stringify(u))});
  });
});'" 2>&1 | sed 's/^/  /'
