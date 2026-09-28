#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 重建 bk-monitor-migrate，验证 403 是否消失（安全方式）====="
echo ""

echo "--- 1. 先保存 job 定义（删除前）---"
kubectl get job bk-monitor-migrate-2 -n blueking -o yaml > /root/bk-monitor-migrate-2.job.yaml 2>&1
echo "  已保存 /root/bk-monitor-migrate-2.job.yaml ($(wc -c < /root/bk-monitor-migrate-2.job.yaml) 字节)"

echo ""
echo "--- 2. 清洗 job yaml（去掉 status/uid 等，便于重建）---"
python3 -c '
import yaml,sys
try:
    d=yaml.safe_load(open("/root/bk-monitor-migrate-2.job.yaml"))
    d.pop("status",None)
    m=d["metadata"]
    for k in ["uid","resourceVersion","creationTimestamp","generation","managedFields","ownerReferences","selfLink"]:
        m.pop(k,None)
    m["annotations"].pop("kubectl.kubernetes.io/last-applied-configuration",None) if m.get("annotations") else None
    d["metadata"]=m
    yaml.safe_dump(d, open("/root/bk-monitor-migrate-2.clean.yaml","w"), default_flow_style=False)
    print("  已生成 clean yaml")
except Exception as e:
    print("  清洗失败:",e)
' 2>&1 | sed 's/^/  /'

echo ""
echo "--- 3. 保留旧 pod 日志（存证）---"
MPOD=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
if [ -n "$MPOD" ]; then
  echo "  旧 pod = $MPOD"
  kubectl logs "$MPOD" -n blueking --all-containers 2>/dev/null | grep -icE '403' | sed 's/^/    旧日志 403 次数: /'
fi

echo ""
echo "--- 4. 删除旧 job ---"
kubectl delete job bk-monitor-migrate-2 -n blueking --wait=false 2>&1 | sed 's/^/  /'
sleep 3

echo ""
echo "--- 5. 从 clean yaml 重建 ---"
kubectl apply -f /root/bk-monitor-migrate-2.clean.yaml 2>&1 | sed 's/^/  /'

echo ""
echo "--- 6. 等 45s 看结果 ---"
sleep 45
kubectl get job -n blueking --no-headers 2>/dev/null | grep -i 'monitor.*migrate' | sed 's/^/  /'
echo ""
MPOD2=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep 'bk-monitor-migrate' | awk '{print $1}' | head -1)
echo "  新 pod = $MPOD2"
if [ -n "$MPOD2" ]; then
  echo "  状态: $(kubectl get pod $MPOD2 -n blueking -o jsonpath='{.status.phase}' 2>/dev/null)"
  echo "  403 次数: $(kubectl logs $MPOD2 -n blueking --all-containers 2>/dev/null | grep -icE '403')"
  echo ""
  echo "  --- 最后 15 行日志 ---"
  kubectl logs "$MPOD2" -n blueking --all-containers --tail=15 2>/dev/null | sed 's/^/    /'
fi
} > /root/redo-migrate.txt 2>&1
cat /root/redo-migrate.txt
