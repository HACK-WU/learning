#!/usr/bin/env bash
NS=blueking
kubectl get deploy -n $NS -o json 2>/dev/null > /tmp/dep.json || { echo "  LINK FAIL"; exit 1; }
cat > /tmp/q.py <<'PY'
import json
TARGETS = """bk-apigateway-dashboard-beat bk-apigateway-dashboard-celery bk-cmdb-monstache
bk-monitor-alarm-access-data bk-monitor-alarm-access-event bk-monitor-alarm-access-event-worker
bk-monitor-alarm-access-real-time-data bk-monitor-alarm-action-cron-worker bk-monitor-alarm-action-worker
bk-monitor-alarm-alert bk-monitor-alarm-alert-worker bk-monitor-alarm-api-cron-worker bk-monitor-alarm-beat
bk-monitor-alarm-composite bk-monitor-alarm-converge-worker bk-monitor-alarm-cron-worker
bk-monitor-alarm-detect bk-monitor-alarm-fta-action-worker bk-monitor-alarm-image-worker
bk-monitor-alarm-long-task-cron-worker bk-monitor-alarm-metadata-task-worker bk-monitor-alarm-nodata
bk-monitor-alarm-report-cron-worker bk-monitor-alarm-service-worker bk-monitor-alarm-trigger
bk-monitor-alarm-webhook-action-worker bk-monitor-healthz bk-monitor-web-beat bk-monitor-web-worker
bk-monitor-web-worker-resource bk-nodeman-backend-celery-beat bk-nodeman-backend-common-pworker
bk-nodeman-backend-common-worker bk-nodeman-backend-sync-host bk-nodeman-backend-sync-host-re
bk-nodeman-backend-sync-process bk-nodeman-backend-sync-watch bkiam-saas-beat bkiam-saas-worker""".split()

def mem_mi(c):
    m=(c.get('resources',{}).get('requests',{}) or {}).get('memory','')
    try:
        if m.endswith('Gi'): return float(m[:-2])*1024
        if m.endswith('Mi'): return float(m[:-2])
        if m.endswith('Ki'): return float(m[:-2])/1024
    except: pass
    return 0.0

d=json.load(open('/tmp/dep.json'))
rows=[]
tot=0
for it in d['items']:
    n=it['metadata']['name']
    if n not in TARGETS: continue
    mm=sum(mem_mi(c) for c in it['spec']['template']['spec'].get('containers',[]))
    r=it['status'].get('readyReplicas',0) or 0
    w=it['spec'].get('replicas',0) or 0
    rows.append((n,r,w,mm))
    tot+=mm
rows.sort(key=lambda x:-x[3])
print("  %-46s %-6s %-9s %s"%("DEPLOY","READY","REQ-MEM","STATE"))
for n,r,w,mm in rows:
    print("  %-46s %-6s %-9s %s"%(n,"%d/%d"%(r,w),"%.0fMi"%mm,"UP" if r>0 else "DOWN"))
print("")
print("  合计 requests: %.0f Mi = %.2f Gi  (共 %d 个)"%(tot,tot/1024,len(rows)))
print("  其中 UP=%d  DOWN=%d"%(sum(1 for x in rows if x[1]>0), sum(1 for x in rows if x[1]==0)))
PY
python3 /tmp/q.py
