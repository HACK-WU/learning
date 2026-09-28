#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. Job 失败详情（events）====="
kubectl describe job bk-monitor-migrate-1 -n blueking 2>/dev/null | tail -25 | sed 's/^/  /'

echo ""
echo "===== 2. 是否存在残留 Pod（看日志）====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'migrate' | sed 's/^/  /' || echo "  (无残留 Pod)"

echo ""
echo "===== 3. bk-monitor release 当前状态 ====="
helm list -A 2>/dev/null | grep -E 'bk-monitor' | sed 's/^/  /'

echo ""
echo "===== 4. 确认 chart 与版本（重建要用）====="
helm list -n blueking -o json 2>/dev/null | python3 -c "
import json,sys
for r in json.load(sys.stdin):
    if r['name']=='bk-monitor':
        print('  chart   =',r['chart'])
        print('  status  =',r['status'])
        print('  updated =',r['updated'])
" 2>/dev/null

echo ""
echo "===== 5. bk-job 版本可用性（基础套餐另一个缺失）====="
echo "  version.yaml 指定: $(grep 'bk-job:' /root/bk72/install/blueking/environments/default/version.yaml)"
echo "  repo 可用:"
helm search repo blueking/bk-job --versions 2>/dev/null | head -4 | sed 's/^/    /'

echo ""
echo "===== 6. 节点管理装好后 GSE 侧是否变化 ====="
kubectl get pods -n blueking --no-headers 2>/dev/null | grep -iE 'gse' | sed 's/^/  /'
} > /root/migrate-record.txt 2>&1
cat /root/migrate-record.txt
