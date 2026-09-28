#!/usr/bin/env bash
echo "===== 内存压力诊断（只读）====="
echo ""
echo "--- 1. 节点总览 ---"
kubectl top nodes 2>&1 | sed 's/^/  /'

echo ""
echo "--- 2. 节点 allocatable vs 已分配 ---"
kubectl describe node 2>/dev/null | grep -A5 -E 'Allocated resources' | head -20 | sed 's/^/  /'
kubectl get nodes -o json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for n in d.get("items",[]):
        a=n["status"].get("allocatable",{})
        c=n["status"].get("capacity",{})
        print("  node:",n["metadata"]["name"])
        print("    capacity mem:",c.get("memory")," cpu:",c.get("cpu"))
        print("    allocatable mem:",a.get("memory")," cpu:",a.get("cpu"))
except Exception as e:
    print("  err",e)
' 2>&1

echo ""
echo "--- 3. 内存占用 Top 25 Pod ---"
kubectl top pods -n blueking --no-headers 2>/dev/null | sort -k3 -hr | head -25 | awk '{printf "  %-52s %-8s %s\n", $1, $2, $3}'

echo ""
echo "--- 4. 各命名空间 Pod 内存合计 ---"
kubectl top pods -A --no-headers 2>/dev/null | python3 -c '
import sys
tot={}
cnt={}
for line in sys.stdin:
    p=line.split()
    if len(p)<4: continue
    ns,name,cpu,mem=p[0],p[1],p[2],p[3]
    def mi(v):
        v=v.strip()
        if v.endswith("Mi"): return int(v[:-2])
        if v.endswith("Gi"): return int(v[:-2])*1024
        if v.endswith("m"): return 0
        return 0
    tot[ns]=tot.get(ns,0)+mi(mem)
    cnt[ns]=cnt.get(ns,0)+1
for ns in sorted(tot,key=lambda x:-tot[x]):
    print("  %-20s pods=%-4d mem=%dMi (%.1fGi)"%(ns,cnt[ns],tot[ns],tot[ns]/1024))
' 2>&1

echo ""
echo "--- 5. 是否有 OOM / Evicted ---"
kubectl get pods -A --no-headers 2>/dev/null | grep -iE 'oom|evicted' | head -10 | sed 's/^/  /'
kubectl get events -A --sort-by='.lastTimestamp' 2>/dev/null | grep -iE 'memory|oom|evict' | tail -8 | cut -c1-160 | sed 's/^/  /'
