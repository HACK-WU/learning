#!/usr/bin/env bash
set -uo pipefail
NS=blueking
MP=bk-mongodb-0

echo "===== 1. 列出所有库 ====="
kubectl exec $MP -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval 'db.adminCommand({listDatabases:1}).databases.forEach(function(d){print(d.name)})'" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. bkrepo 相关库 + 集合 ====="
kubectl exec $MP -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval '
db.adminCommand({listDatabases:1}).databases.forEach(function(d){
  var n=d.name;
  if(/repo|auth|bk/i.test(n)){
    print(\"DB: \"+n);
    db.getSiblingDB(n).getCollectionNames().forEach(function(c){print(\"    \"+c)});
  }
});'" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 找 user/account 集合并打印 ====="
kubectl exec $MP -n $NS -- bash -c "mongo --quiet -u root -p blueking --authenticationDatabase admin --eval '
db.adminCommand({listDatabases:1}).databases.forEach(function(d){
  var n=d.name; var dbx=db.getSiblingDB(n);
  dbx.getCollectionNames().forEach(function(c){
    if(/user|account|credential/i.test(c)){
      print(\"=== \"+n+\"/\"+c+\" (count=\"+dbx.getCollection(c).count()+\") ===\");
      dbx.getCollection(c).find().limit(5).forEach(function(u){
        print(\"    \"+JSON.stringify(u).slice(0,300));
      });
    }
  });
});'" 2>&1 | sed 's/^/  /'
