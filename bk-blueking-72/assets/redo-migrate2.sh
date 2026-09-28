#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 修正清洗：去掉 controller-uid 与 selector，让 k8s 自动生成 ====="

python3 -c '
import yaml
d=yaml.safe_load(open("/root/bk-monitor-migrate-2.job.yaml"))
d.pop("status",None)
m=d["metadata"]
for k in ["uid","resourceVersion","creationTimestamp","generation","managedFields","ownerReferences","selfLink"]:
    m.pop(k,None)
if m.get("annotations"):
    m["annotations"].pop("kubectl.kubernetes.io/last-applied-configuration",None)
d["metadata"]=m

# 关键：去掉 selector（让 k8s 自动生成）
d["spec"].pop("selector",None)

# 关键：去掉 template 里的 controller-uid / job-name 标签
t=d["spec"]["template"]["metadata"]
if t.get("labels"):
    for k in ["controller-uid","batch.kubernetes.io/controller-uid","job-name","batch.kubernetes.io/job-name"]:
        t["labels"].pop(k,None)
tm=t.get("annotations")
if tm:
    for k in list(tm.keys()):
        if "last-applied" in k: tm.pop(k,None)

# 允许重跑
d["spec"]["backoffLimit"]=6
d["spec"].pop("completions",None) if d["spec"].get("completions")==1 else None

yaml.safe_dump(d, open("/root/bk-monitor-migrate-2.clean.yaml","w"), default_flow_style=False)
print("  clean yaml 重新生成 OK")
' 2>&1 | sed 's/^/  /'

echo ""
echo "--- 应用 ---"
kubectl apply -f /root/bk-monitor-migrate-2.clean.yaml 2>&1 | sed 's/^/  /'

echo ""
echo "--- 等 60s 看结果 ---"
sleep 60
kubectl get job -n blueking --no-headers 2>/dev/null | grep -i 'monitor.*migrate' | sed 's/^/  /'
echo ""
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
echo "  新 pod = $MPOD"
if [ -n "$MPOD" ]; then
  echo "  状态: $(kubectl get pod $MPOD -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)"
  echo "  403 次数: $(kubectl logs $MPOD -n blueking --all-containers 2>/dev/null | grep -icE '403')"
  echo ""
  echo "  --- 最后 20 行日志 ---"
  kubectl logs "$MPOD" -n blueking --all-containers --tail=20 2>/dev/null | sed 's/^/    /'
fi
} > /root/redo2.txt 2>&1
cat /root/redo2.txt
