#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 节点资源现状（决定还能装多少）====="
kubectl top nodes 2>/dev/null | sed 's/^/  /'
echo ""
echo "  节点容量:"
kubectl describe node 2>/dev/null | grep -A2 -E '^Allocated resources' | head -6 | sed 's/^/  /'
kubectl get nodes -o jsonpath='{range .items[*]}  {.metadata.name}  可分配: cpu={.status.allocatable.cpu} mem={.status.allocatable.memory}{"\n"}{end}' 2>/dev/null

echo ""
echo "===== 2. 当前 blueking 命名空间总资源请求 ====="
kubectl get pods -n "$NS" -o json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
tc=tr=0
for p in d.get('items',[]):
    for c in p['spec'].get('containers',[]):
        r=c.get('resources',{}).get('requests',{})
        tc+=int(r.get('cpu','0').replace('m','')) if 'cpu' in r else 0
        mem=r.get('memory','0')
        if mem.endswith('Gi'): tr+=float(mem[:-2])*1024
        elif mem.endswith('Mi'): tr+=float(mem[:-2])
        elif mem.endswith('Ki'): tr+=float(mem[:-2])/1024
print(f'  总 CPU 请求: {tc}m ({tc/1000:.2f} 核)')
print(f'  总内存请求: {tr:.0f} Mi ({tr/1024:.2f} Gi)')
" 2>/dev/null

echo ""
echo "===== 3. 缺失模块的官方配置（看是否 enabled）====="
for m in bk_nodeman bk_monitorv3 bk_job bk_log_search bk_ci bk_itsm bk_sops bk_bcs bk_flow_engine bk_notice lesscode; do
  f="/root/bk72/install/bk-config/$m"
  [ -d "$f" ] || continue
  en=$(grep -rhoE '^\s*(enabled|enable)\s*:\s*(true|false)' "$f" 2>/dev/null | head -1 | tr -d ' ')
  printf "  %-18s enabled=%s\n" "$m" "${en:-未明确}"
done

echo ""
echo "===== 4. 缺失模块的 values 文件大小（粗略看复杂度）====="
for m in bk_nodeman bk_monitorv3 bk_job bk_log_search bk_ci bk_itsm bk_sops; do
  f="/root/bk72/install/bk-config/$m"
  [ -d "$f" ] || continue
  sz=$(du -sh "$f" 2>/dev/null | awk '{print $1}')
  nf=$(find "$f" -type f 2>/dev/null | wc -l)
  printf "  %-18s 大小=%-8s 文件数=%s\n" "$m" "$sz" "$nf"
done
