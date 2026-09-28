#!/usr/bin/env bash
NS=blueking
echo "=== 1. 内存占用 TOP 25 Pod ==="
kubectl top pod -n $NS --no-headers 2>/dev/null | sort -k3 -h -r | head -25 | awk '{printf "  %-56s %s\n",$1,$3}' | sed 's/^/  /'

echo ""
echo "=== 2. 各命名空间内存 requests 合计 ==="
for n in blueking monitoring kube-system default; do
  v=$(kubectl get pods -n $n -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
t=0
for p in d.get('items',[]):
    if p['status'].get('phase')!='Running': continue
    for c in p['spec']['containers']:
        r=(c.get('resources') or {}).get('requests') or {}
        m=r.get('memory','0')
        try:
            if m.endswith('Gi'): t+=float(m[:-2])
            elif m.endswith('Mi'): t+=float(m[:-2])/1024
            elif m.endswith('G'): t+=float(m[:-1])
            elif m.endswith('M'): t+=float(m[:-1])/1024
        except: pass
print('%.2f'%t)
")
  echo "  $n : ${v} GiB"
done

echo ""
echo "=== 3. 可被裁剪（非本批）的大户 ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3=="Running"{print $1}' > /tmp/run.txt
kubectl top pod -n $NS --no-headers 2>/dev/null | sort -k3 -h -r | head -40 | while read p c rest; do
  case "$p" in
    bk-repo-*|bk-applog-*|bk-log-*|bkpaas3-svc-bkrepo-*|bk-cmdb-*)
      echo "  [可裁] $p  $c" ;;
  esac
done | head -20
