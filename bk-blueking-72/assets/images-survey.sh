#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. 各组件实际拉取的镜像地址（当前集群）====="
echo "  --- helm release 使用的 chart 与 appVersion ---"
helm list -A 2>/dev/null | head -30 | sed 's/^/  /'

echo ""
echo "===== 2. 关键组件 Pod 的真实 image（含 registry 前缀）====="
kubectl get pods -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
seen={}
for p in d.get('items',[]):
    name=p['metadata']['name']
    for c in p['spec'].get('containers',[]) + p['spec'].get('initContainers',[]):
        img=c.get('image','')
        if img:
            repo=img.rsplit(':',1)[0] if ':' in img else img
            seen.setdefault(repo,[]).append(name.split('-')[0:3])
print('  去重后镜像仓库数:', len(seen))
for r in sorted(seen):
    print('   ', r)
" 2>/dev/null

echo ""
echo "===== 3. 镜像仓库地址（registry）统计 ====="
kubectl get pods -n blueking -o json 2>/dev/null | python3 -c "
import json,sys,collections
d=json.load(sys.stdin)
c=collections.Counter()
for p in d.get('items',[]):
    for ct in p['spec'].get('containers',[]) + p['spec'].get('initContainers',[]):
        img=ct.get('image','')
        if img:
            reg=img.split('/')[0]
            c[reg]+=1
for r,n in c.most_common():
    print('   %-40s 出现 %d 次' % (r,n))
" 2>/dev/null

echo ""
echo "===== 4. 特定组件镜像明细（本次涉及的）====="
for kw in gse nodeman monitor job apigateway esb; do
  echo "  --- $kw ---"
  kubectl get pods -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
kw='$kw'
d=json.load(sys.stdin)
s=set()
for p in d.get('items',[]):
    if kw in p['metadata']['name']:
        for c in p['spec'].get('containers',[]) + p['spec'].get('initContainers',[]):
            if c.get('image'): s.add(c['image'])
for i in sorted(s): print('    ', i)
" 2>/dev/null
done

echo ""
echo "===== 5. helm repo 配置（chart 来源）====="
helm repo list 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 6. 容器内是否保留源码（抽样：monitor web）====="
MP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor-web' | grep Running | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  kubectl exec "$MP" -n blueking -- sh -c '
    echo "  应用目录:"
    ls /app 2>/dev/null | head -10
    echo "  是否有 .py 源码:"
    find /app -maxdepth 3 -name "*.py" 2>/dev/null | head -5
    echo "  是否有 .git:"
    find / -maxdepth 4 -name ".git" -type d 2>/dev/null | head -3
  ' 2>&1 | sed 's/^/  /'
fi

echo ""
echo "===== 7. GSE 容器内源码形态 ====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
if [ -n "$GP" ]; then
  kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
    echo "  GSE 安装目录:"
    ls /data/gse 2>/dev/null | head -12
    echo "  二进制文件（是否有编译产物）:"
    find /data/gse -maxdepth 3 -type f -executable 2>/dev/null | head -8
    echo "  是否有源码文件:"
    find /data/gse -maxdepth 3 \( -name "*.py" -o -name "*.cc" -o -name "*.go" \) 2>/dev/null | head -5
  ' 2>&1 | sed 's/^/  /'
fi
} > /root/images-survey.txt 2>&1
cat /root/images-survey.txt
