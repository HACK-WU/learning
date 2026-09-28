#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 找到 bk-gse-certs 在哪个 namespace ====="
kubectl get secret --all-namespaces 2>/dev/null | grep -i 'bk-gse-certs' | sed 's/^/  /'
echo "  (若为空则名称不同，列所有 gse 相关 secret)"
kubectl get secret --all-namespaces 2>/dev/null | grep -i 'gse' | sed 's/^/  /'

echo ""
echo "===== 2. GSE data pod 实际用的 secret（重新查挂载）====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
echo "  pod = $GP"
kubectl get pod "$GP" -n blueking -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print("  namespace:", d["metadata"]["namespace"])
for c in d["spec"]["containers"]:
    for m in c.get("volumeMounts",[]):
        if "cert" in m["mountPath"]:
            print("   container:",c["name"],"mount:",m["mountPath"],"volume:",m["name"])
for v in d["spec"]["volumes"]:
    s=v.get("secret",{})
    if s: print("   volume:",v["name"],"-> secret:",s.get("secretName"))
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 该 secret 的所有者（helm release）====="
for ns in blueking default bk-gse; do
  echo "  --- ns=$ns ---"
  kubectl get secret bk-gse-certs -n "$ns" -o jsonpath='  labels={.metadata.labels}{"\n"}  annotations={.metadata.annotations}{"\n"}' 2>/dev/null | sed 's/^/  /'
done
} > /root/secret-b.txt 2>&1
cat /root/secret-b.txt
