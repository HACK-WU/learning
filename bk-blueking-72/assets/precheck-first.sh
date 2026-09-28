#!/usr/bin/env bash
# seq=first 部署前预检：资源 / 镜像 / 依赖
set -uo pipefail
NS=blueking
B=/root/bk72/install/blueking

echo "===== 1. seq=first 包含哪些 release ====="
python3 - "$B/base-blueking.yaml.gotmpl" <<'PY'
import re,sys
txt=open(sys.argv[1]).read()
cur=None; out=[]
for line in txt.splitlines():
    m=re.match(r'\s*- name:\s*(\S+)', line)
    if m: cur=m.group(1); out.append([cur,None])
    m2=re.match(r'\s*seq:\s*(\S+)', line)
    if m2 and out: out[-1][1]=m2.group(1)
for n,s in out:
    if s=='first': print(f"  {n}")
PY

echo ""
echo "===== 2. 当前资源余量 ====="
kubectl top nodes 2>/dev/null | head -5
echo "--- 可分配 ---"
kubectl describe nodes 2>/dev/null | grep -A5 'Allocated resources' | head -6

echo ""
echo "===== 3. 存储余量（PVC 已用 160Gi）====="
kubectl get pvc -n "$NS" --no-headers 2>/dev/null | awk '{s+=$3} END {print "  已申请 PVC 总量(含单位混合，仅参考)"}'
df -h / 2>/dev/null | tail -1

echo ""
echo "===== 4. 已缓存镜像数（判断新批次需拉多少）====="
for n in k8s-c1-calico-control-plane k8s-c1-calico-worker k8s-c1-calico-worker2; do
  echo "  $n: $(docker exec $n ctr -n k8s.io images list 2>/dev/null | wc -l)"
done

echo ""
echo "===== 5. failed release 的实际影响（Pod 是否健康）====="
echo "  注意：release=failed 多为超时导致，Pod 实际已 Running"
kubectl get pods -n "$NS" --no-headers 2>/dev/null | grep -cE '([0-9]+)/\1' | xargs echo "  就绪 Pod 数:"
