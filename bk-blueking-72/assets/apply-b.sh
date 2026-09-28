#!/usr/bin/env bash
# 方案B：关闭纯后台任务（可逆）
# 前置：先生成恢复脚本，再动手
NS=blueking
TS=$(date +%Y%m%d-%H%M%S)
OUT=/root/bk-lite-b
mkdir -p "$OUT"

# 39 个后台任务中保留 4 个（可能间接影响页面交互，见文档 14）
#   bk-cmdb-monstache      CMDB->ES 同步，关掉全文检索数据陈旧
#   bk-monitor-web-beat    监控 web 定时调度
#   bk-monitor-web-worker  监控 web 异步任务（保存策略等）
#   bk-monitor-healthz     监控健康检查
cat > "$OUT/targets.txt" <<'EOF'
bk-apigateway-dashboard-beat
bk-apigateway-dashboard-celery
bk-monitor-alarm-access-data
bk-monitor-alarm-access-event
bk-monitor-alarm-access-event-worker
bk-monitor-alarm-access-real-time-data
bk-monitor-alarm-action-cron-worker
bk-monitor-alarm-action-worker
bk-monitor-alarm-alert
bk-monitor-alarm-alert-worker
bk-monitor-alarm-api-cron-worker
bk-monitor-alarm-beat
bk-monitor-alarm-composite
bk-monitor-alarm-converge-worker
bk-monitor-alarm-cron-worker
bk-monitor-alarm-detect
bk-monitor-alarm-fta-action-worker
bk-monitor-alarm-image-worker
bk-monitor-alarm-long-task-cron-worker
bk-monitor-alarm-metadata-task-worker
bk-monitor-alarm-nodata
bk-monitor-alarm-report-cron-worker
bk-monitor-alarm-service-worker
bk-monitor-alarm-trigger
bk-monitor-alarm-webhook-action-worker
bk-monitor-web-worker-resource
bk-nodeman-backend-celery-beat
bk-nodeman-backend-common-pworker
bk-nodeman-backend-common-worker
bk-nodeman-backend-sync-host
bk-nodeman-backend-sync-host-re
bk-nodeman-backend-sync-process
bk-nodeman-backend-sync-watch
bkiam-saas-beat
bkiam-saas-worker
EOF

echo "TARGETS=$(wc -l < "$OUT/targets.txt")"

echo ""
echo "=== 1. 变更前快照 ==="
kubectl get deploy -n $NS -o json > "$OUT/dep-before-$TS.json" 2>/dev/null
echo "  deploy json: $OUT/dep-before-$TS.json"
echo "  pods now:    $(kubectl get pods -n $NS --no-headers 2>/dev/null | wc -l)"
echo "  --- WSL mem ---"
free -g | sed -n '1,2p' | sed 's/^/  /'
echo "  --- PSI ---"
cat /proc/pressure/memory 2>/dev/null | sed 's/^/  /'

echo ""
echo "=== 2. 生成恢复脚本（关键：记录原副本数） ==="
python3 - "$OUT" "$TS" <<'PY'
import json,sys
out,ts=sys.argv[1],sys.argv[2]
targets=[l.strip() for l in open(out+'/targets.txt') if l.strip()]
d=json.load(open('%s/dep-before-%s.json'%(out,ts)))
orig={}
for it in d['items']:
    n=it['metadata']['name']
    if n in targets:
        orig[n]=it['spec'].get('replicas',0) or 0
lines=["#!/usr/bin/env bash","# 恢复脚本 生成时间: %s"%ts,"# 用法: bash %s/restore.sh"%out,"NS=blueking",""]
for n,r in sorted(orig.items()):
    lines.append("kubectl scale deploy -n $NS --replicas=%d %s"%(r,n))
open(out+'/restore.sh','w').write("\n".join(lines)+"\n")
print("  restore.sh: %s/restore.sh (%d 条)"%(out,len(orig)))
# 打印非1的原值，避免误恢复
odd={k:v for k,v in orig.items() if v!=1}
print("  原副本数!=1 的（恢复时不能一律写1）: %s"%(odd if odd else "无"))
PY

echo ""
echo "=== 3. 执行 scale --replicas=0 ==="
kubectl scale deploy -n $NS --replicas=0 $(tr '\n' ' ' < "$OUT/targets.txt") 2>&1 | tail -5
echo "  scale 命令已下发"
