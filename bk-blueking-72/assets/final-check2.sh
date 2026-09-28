#!/usr/bin/env bash
D=/mnt/d/projects/learning/bk-blueking-72
NS=blueking

echo "=== 1. 磁盘上的 md 文件（全） ==="
ls $D/*.md 2>/dev/null | xargs -n1 basename

echo ""
echo "=== 2. 索引里的链接是否都能打开 ==="
grep -ohE '\]\([^)]*\.md\)' $D/README-验证报告索引.md 2>/dev/null | sed 's/](\(.*\))/\1/' | while read f; do
  [ -e "$D/$f" ] && echo "  OK   $f" || echo "  断链 $f"
done

echo ""
echo "=== 3. 11 个未还原探针：原始值到底是什么 ==="
kubectl get deploy -n $NS bk-repo-bkrepo-auth -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['spec']['template']['spec']['containers'][0]
print('  当前 liveness:', json.dumps(c.get('livenessProbe'),ensure_ascii=False))
print('  当前 readiness:', json.dumps(c.get('readinessProbe'),ensure_ascii=False))
"

echo ""
echo "=== 4. 原始值从 helm manifest 取（权威来源） ==="
kubectl get secret -n $NS sh.helm.release.v1.bk-repo.v1 -o jsonpath='{.data.release}' 2>/dev/null \
 | base64 -d 2>/dev/null | base64 -d 2>/dev/null | gunzip 2>/dev/null \
 | grep -oE 'failureThreshold[^,}]{0,20}' | head -3
echo "  (上面是 release 里的原始 failureThreshold)"

echo ""
echo "=== 5. cronjob 有没有在跑（7 个） ==="
kubectl get cronjob -n $NS --no-headers 2>/dev/null | awk '{print "  "$1"  schedule="$2"  suspend="$4}'

echo ""
echo "=== 6. cronjob 最近一次执行 ==="
kubectl get jobs -n $NS --no-headers 2>/dev/null | tail -5 | awk '{print "  "$1" "$2" "$3}'
