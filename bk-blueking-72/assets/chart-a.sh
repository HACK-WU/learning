#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 拉 bk-gse-ce chart 看 bk-gse-certs 模板 ====="
rm -rf /tmp/gsechart && mkdir -p /tmp/gsechart
helm pull blueking/bk-gse-ce --version v2.1.6-beta.65 --destination /tmp/gsechart --untar 2>&1 | head -3
grep -rn 'bk-gse-certs' /tmp/gsechart/ 2>/dev/null | head -5 | sed 's/^/  /'

echo ""
echo "  --- 模板里 apigw_jwt 怎么来的 ---"
grep -rn -B5 -A10 'apigw_jwt' /tmp/gsechart/ 2>/dev/null | head -40 | sed 's/^/  /'

echo ""
echo "===== 2. 有没有 RBAC 允许 job 写 configmap（判断 Job 写入说）====="
grep -rn -A12 'configmaps' /tmp/gsechart/ 2>/dev/null | head -25 | sed 's/^/  /'

echo ""
echo "===== 3. 集群里有没有对应 Role/ClusterRole ====="
kubectl get role,clusterrole -A --no-headers 2>/dev/null | grep -i 'gse' | head -5 | sed 's/^/  /'

echo ""
echo "===== 4. 决定性：ConfigMap 的 managedFields（谁最后写的）====="
kubectl get cm bk-gse-certs -n blueking -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for mf in d["metadata"].get("managedFields",[]):
    print("  manager:",mf.get("manager")," operation:",mf.get("operation"))
    fields=mf.get("fieldsV1",{})
    s=json.dumps(fields)
    if "apigw_jwt" in s:
        print("     -> 该 manager 管理了 apigw_jwt.crt")
' 2>&1 | sed 's/^/  /'
} > /root/chart-a.txt 2>&1
cat /root/chart-a.txt
