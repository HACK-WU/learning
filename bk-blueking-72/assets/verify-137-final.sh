#!/usr/bin/env bash
# 用途：拿到决定性证据——137 到底是 OOM 还是探针/脚本 kill
set -uo pipefail
NS=blueking
POD=bk-redis-cluster-2
NODE=k8s-c1-calico-worker

echo "===== 1. 完整容器状态（含 OOMKilled 标志）====="
kubectl get pod "$POD" -n "$NS" -o json 2>&1 | python3 -c "
import json,sys
d=json.load(sys.stdin)
for cs in d['status'].get('containerStatuses',[]):
    print('name:',cs['name'])
    print('lastState:',json.dumps(cs.get('lastState',{}),ensure_ascii=False))
    print('state:',json.dumps(cs.get('state',{}),ensure_ascii=False))
"

echo ""
echo "===== 2. 全部事件（含 Killing 原因原文）====="
kubectl get events -n "$NS" --field-selector involvedObject.name="$POD" --sort-by=.lastTimestamp 2>&1 | tail -12

echo ""
echo "===== 3. 节点真实 OOM 记录（dmesg，需 root）====="
wsl.exe -d Ubuntu -- bash -c 'dmesg -T 2>/dev/null | grep -iE "oom|killed process" | tail -10' 2>&1 | head -12

echo ""
echo "===== 4. 容器内 cgroup 内存限制（v2）====="
echo "无 limits 时 = 节点内存上限，不会主动 OOM"

echo ""
echo "===== 5. 关键：ping_liveness_local.sh 脚本内容 ====="
echo "该脚本在镜像内，若连不上 redis 会 exit 非0"
echo "但 liveness 失败 → kubelet 发 SIGTERM(143)，非 137"
echo "137 = 128+9 = SIGKILL，通常是 OOM killer 或强制 kill"
