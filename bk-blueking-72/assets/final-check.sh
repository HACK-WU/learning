#!/usr/bin/env bash
NS=blueking
D=/mnt/d/projects/learning/bk-blueking-72

echo "=== 1. 还剩下没起的组件（含 svc 级、非 deploy 的） ==="
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print "  deploy "$1}'
kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print "  sts   "$1}'
echo "  --- 上面是 deploy/sts，下面是 ds/cronjob/job ---"
kubectl get ds -n $NS --no-headers 2>/dev/null | awk '$2!~/^[0-9]/||$2=="0"{print "  ds    "$1" ("$2")"}'
kubectl get cronjob -n $NS --no-headers 2>/dev/null | awk '{print "  cj    "$1}'

echo ""
echo "=== 2. 所有 pod 状态汇总（看有没有异常态） ==="
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn

echo ""
echo "=== 3. 探针是否都已还原（对照备份） ==="
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
sus=[]
for it in d['items']:
    n=it['metadata']['name']
    c=it['spec']['template']['spec']['containers'][0]
    lp=c.get('livenessProbe') or {}
    init=lp.get('initialDelaySeconds',999)
    ft=lp.get('failureThreshold',999)
    # 180s/12 是验证时放宽过的值，出现即未还原
    if init==180 or ft==12:
        sus.append((n,init,ft))
if sus:
    print('  [未还原] %d 个:'%len(sus))
    for n,i,f in sus: print('     %-34s init=%s fail=%s'%(n,i,f))
else:
    print('  OK 没有遗留的 180s/12 放宽值')
"

echo ""
echo "=== 4. 文档清单（看有没有断链/缺失） ==="
ls $D/*.md 2>/dev/null | xargs -n1 basename | sed 's/^/  /' | head -30

echo ""
echo "=== 5. 索引文件里引用了但磁盘不存在的文件（断链检查） ==="
grep -ohE '\]\([0-9][^)]*\.md\)' $D/README-验证报告索引.md 2>/dev/null | tr -d '](' | sed 's/)//' | while read f; do
  [ -f "$D/$f" ] || echo "  断链: $f"
done
echo "  (空=无断链)"

echo ""
echo "=== 6. 各报告里的「遗留」章节（汇总待办） ==="
grep -A6 '^## .*遗留' $D/2[0-2]*.md 2>/dev/null | grep -E '^\S+[-:]?[0-9]*[-:]?\s*\|' | head -12
