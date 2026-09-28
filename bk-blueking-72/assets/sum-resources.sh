#!/usr/bin/env bash
# 用途：精确汇总 base-storage 的资源 requests（按组件，含副本数）与 PVC 总量
set -uo pipefail
OUT=/root/bk72/render_test/base-storage-render.yaml

echo "===== 1. 每个工作负载的副本数 + requests ====="
awk '
/^kind: (StatefulSet|Deployment)/ { kind=$2 }
/^  name: / { nm=$2 }
/^  replicas: / { rep=$2 }
/^ *requests:/ { inreq=1; cpu=""; mem=""; next }
inreq && /cpu:/ { cpu=$2 }
inreq && /memory:/ { mem=$2; inreq=0
  if (nm!="") printf "%-45s %-14s rep=%-3s cpu=%-8s mem=%s\n", nm, kind, (rep==""?"1":rep), (cpu=="-":"-"):"", mem
  rep=""
}
' "$OUT" 2>/dev/null | sort -u | head -30

echo ""
echo "===== 2. 内存总量精确计算（考虑副本数）====="
python3 - <<'PY'
import re
try:
    txt=open('/root/bk72/render_test/base-storage-render.yaml').read()
except Exception as e:
    print("读取失败:",e); raise SystemExit

def to_mi(s):
    s=s.strip().strip('"\'')
    m=re.match(r'^(\d+(?:\.\d+)?)\s*(Ki|Mi|Gi|Ti|K|M|G|T)?$', s)
    if not m: return 0.0
    v=float(m.group(1)); u=m.group(2) or ''
    return v*{'Ki':1/1024,'K':1/1024,'Mi':1,'M':1,'Gi':1024,'G':1024,'Ti':1024*1024,'T':1024*1024}.get(u,1/1024/1024)

# 按文档切块
blocks=re.split(r'(?m)^---\s*$', txt)
total=0.0; rows=[]
for b in blocks:
    km=re.search(r'(?m)^kind:\s*(\S+)', b)
    nm=re.search(r'(?m)^  name:\s*(\S+)', b)
    if not km or not nm: continue
    if km.group(1) not in ('StatefulSet','Deployment'): continue
    rp=re.search(r'(?m)^  replicas:\s*(\d+)', b)
    rep=int(rp.group(1)) if rp else 1
    req=re.search(r'(?m)^\s*requests:\s*$(.*?)(?=^\s{0,6}\S)', b, re.S|re.M)
    mem=0.0; cpu=0.0
    if req:
        mm=re.search(r'memory:\s*(\S+)', req.group(1))
        cm=re.search(r'(?m)^\s+cpu:\s*(\S+)', req.group(1))
        if mm: mem=to_mi(mm.group(1))
        if cm:
            c=cm.group(1)
            cpu=float(c[:-1])/1000 if c.endswith('m') else float(c)
    t=mem*rep
    total+=t
    if mem>0: rows.append((nm.group(1),km.group(1),rep,mem,cpu,t))

for r in sorted(rows,key=lambda x:-x[5]):
    print(f"{r[0]:<45} {r[1]:<12} rep={r[2]:<3} {r[3]:>8.0f}Mi x{r[2]} = {r[5]:>8.0f}Mi  cpu≈{r[4]*r[2]:.2f}")
print("-"*100)
print(f"★ 内存 requests 合计: {total:.0f}Mi = {total/1024:.2f}Gi")
PY

echo ""
echo "===== 3. PVC 总量 ====="
grep -oE 'storage: *"?[0-9]+Gi"?' "$OUT" | grep -oE '[0-9]+' | paste -sd+ | bc 2>/dev/null | xargs -I{} echo "PVC 总需求: {} Gi"
