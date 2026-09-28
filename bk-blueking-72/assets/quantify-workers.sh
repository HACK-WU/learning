#!/usr/bin/env bash
NS=blueking
echo "=== 39个后台任务的 副本数 / 状态 / 内存requests ==="
printf "  %-46s %-6s %-10s %s\n" "DEPLOY" "READY" "REQ-MEM" "STATUS"
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for it in d['items']:
    n=it['metadata']['name']
    st=it['spec']['template']['spec']
    mem=0
    for c in st.get('containers',[]):
        m=(c.get('resources',{}).get('requests',{}) or {}).get('memory','0')
        # 解析 Mi/Gi
        try:
            if m.endswith('Gi'): mem+=float(m[:-2])*1024
            elif m.endswith('Mi'): mem+=float(m[:-2])
            elif m.endswith('m'): mem+=float(m[:-1])/1024/1024
        except: pass
    r=it['status'].get('readyReplicas',0) or 0
    want=it['spec'].get('replicas',0)
    print('  %-46s %-6s %-10s %s'%('-', '%d/%d'%(r,want), '%.0fMi'%mem if mem else '-', 'OK' if r>0 else 'DOWN'))
" | grep -f <(printf '%s\n' bk-apigateway-dashboard-beat bk-apigateway-dashboard-celery bk-cmdb-monstache bk-monitor-alarm-access-data bk-monitor-alarm-access-event bk-monitor-alarm-access-event-worker bk-monitor-alarm-access-real-time-data bk-monitor-alarm-action-cron-worker bk-monitor-alarm-action-worker bk-monitor-alarm-alert bk-monitor-alarm-alert-worker bk-monitor-alarm-api-cron-worker bk-monitor-alarm-beat bk-monitor-alarm-composite bk-monitor-alarm-converge-worker bk-monitor-alarm-cron-worker bk-monitor-alarm-detect bk-monitor-alarm-fta-action-worker bk-monitor-alarm-image-worker bk-monitor-alarm-long-task-cron-worker bk-monitor-alarm-metadata-task-worker bk-monitor-alarm-nodata bk-monitor-alarm-report-cron-worker bk-monitor-alarm-service-worker bk-monitor-alarm-trigger bk-monitor-alarm-webhook-action-worker bk-monitor-healthz bk-monitor-web-beat bk-monitor-web-worker bk-monitor-web-worker-resource bk-nodeman-backend-celery-beat bk-nodeman-backend-common-pworker bk-nodeman-backend-common-worker bk-nodeman-backend-sync-host bk-nodeman-backend-sync-host-re bk-nodeman-backend-sync-process bk-nodeman-backend-sync-watch bkiam-saas-beat bkiam-saas-worker) 2>/dev/null || echo "  (fallback)"
echo ""
echo "=== 实际内存占用 TOP (metrics-server 若不可达则空) ==="
kubectl top pod -n $NS --no-headers 2>/dev/null | sort -k3 -h -r | head -15 | sed 's/^/  /'
