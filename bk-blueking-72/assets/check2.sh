#!/usr/bin/env bash
echo "===== 遗留 2 个 CrashLoopBackOff 排查 ====="
echo ""
for P in bk-monitor-web-6699f4d79c-tnw4t bk-monitor-web-query-api-699f99c694-x4pr5; do
  echo "=== $P ==="
  echo "--- init 容器状态 ---"
  kubectl get pod "$P" -n blueking -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for c in d["status"].get("initContainerStatuses",[]):
    st=c.get("state",{})
    w=st.get("waiting",{})
    t=st.get("terminated",{})
    print("   init:",c["name"]," ready=",c["ready"]," reason=",w.get("reason") or t.get("reason")," exit=",t.get("exitCode"))
' 2>&1
  echo "--- init 日志（前30行）---"
  kubectl logs "$P" -n blueking --all-containers --tail=30 2>/dev/null | cut -c1-180 | sed 's/^/   /'
  echo ""
done
