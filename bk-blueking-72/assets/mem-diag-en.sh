#!/usr/bin/env bash
echo "===== MEMORY DIAGNOSIS (read-only) ====="
echo ""
echo "--- 1. Nodes ---"
kubectl top nodes 2>&1 | sed 's/^/  /'

echo ""
echo "--- 2. Node capacity vs allocatable ---"
kubectl get nodes -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for n in d.get("items",[]):
        a=n["status"].get("allocatable",{})
        c=n["status"].get("capacity",{})
        print("  node:",n["metadata"]["name"])
        print("    capacity   mem:",c.get("memory")," cpu:",c.get("cpu"))
        print("    allocatable mem:",a.get("memory")," cpu:",a.get("cpu"))
        for cond in n["status"].get("conditions",[]):
            if cond["type"] in ("MemoryPressure","DiskPressure","Ready"):
                print("    cond %s=%s"%(cond["type"],cond["status"]))
except Exception as e:
    print("  err",e)
' 2>&1

echo ""
echo "--- 3. Top 25 pods by memory (blueking) ---"
kubectl top pods -n blueking --no-headers 2>/dev/null | sort -k3 -hr | head -25 | awk '{printf "  %-52s %-8s %s\n", $1, $2, $3}'

echo ""
echo "--- 4. Memory total per namespace ---"
kubectl top pods -A --no-headers 2>/dev/null | python3 -c '
import sys
tot={};cnt={}
def mi(v):
    v=v.strip()
    if v.endswith("Mi"): return int(v[:-2])
    if v.endswith("Gi"): return int(v[:-2])*1024
    return 0
for line in sys.stdin:
    p=line.split()
    if len(p)<4: continue
    ns,mem=p[0],p[3]
    tot[ns]=tot.get(ns,0)+mi(mem)
    cnt[ns]=cnt.get(ns,0)+1
for ns in sorted(tot,key=lambda x:-tot[x]):
    print("  %-22s pods=%-4d mem=%dMi (%.1fGi)"%(ns,cnt[ns],tot[ns],tot[ns]/1024))
' 2>&1

echo ""
echo "--- 5. OOM / Evicted ---"
kubectl get pods -A --no-headers 2>/dev/null | grep -iE 'oom|evicted' | head -10 | sed 's/^/  /'
echo "  (empty = none)"
echo ""
kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | grep -iE 'memory|oom|evict' | tail -8 | cut -c1-150 | sed 's/^/  /'
