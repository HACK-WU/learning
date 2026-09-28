#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. bk-gse-apigw-sync-1.yaml 内容（官方同步 Job？）====="
cat /root/bk72/install/bk-job-backup-20260923-125630/bk-gse-apigw-sync-1.yaml 2>/dev/null | head -60 | sed 's/^/  /'

echo ""
echo "===== 2. 该 backup 目录里有什么 ====="
ls -la /root/bk72/install/bk-job-backup-20260923-125630/ 2>/dev/null | head -20 | sed 's/^/  /'

echo ""
echo "===== 3. 这个 job 在集群里跑过吗 ====="
kubectl get job -n blueking --no-headers 2>/dev/null | grep -i 'gse.*apigw\|apigw.*sync' | sed 's/^/  /'

echo ""
echo "===== 4. 关键：bk-gse 的 helm values 里 apigwSync 段完整内容 ====="
helm get values bk-gse -n blueking 2>/dev/null | python3 -c '
import sys,yaml
try:
    d=yaml.safe_load(sys.stdin) or {}
    a=d.get("apigwSync") or {}
    print("  apigwSync =", yaml.dump(a, default_flow_style=False, allow_unicode=True)[:1500])
except Exception as e:
    print("  parse err:",e)
' 2>&1 | sed 's/^/  /'
} > /root/sync-job.txt 2>&1
cat /root/sync-job.txt
