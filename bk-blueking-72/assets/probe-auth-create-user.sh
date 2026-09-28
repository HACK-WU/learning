#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 从 app.jar 挖 User 文档结构与认证逻辑 ====="
AP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | grep Running | awk '{print $1}' | head -1)
kubectl exec $AP -n $NS -- bash -c "
cd /tmp && unzip -o -q /data/workspace/app.jar 'BOOT-INF/classes/**' -d /tmp/jarx 2>/dev/null
ls /tmp/jarx/BOOT-INF/classes/ 2>/dev/null
echo '--- 找 auth 相关 class ---'
find /tmp/jarx -iname '*User*' 2>/dev/null | head -20
find /tmp/jarx -iname '*bkrepo*' -o -iname '*Token*' 2>/dev/null | head -10
" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 看 auth 配置文件里 platform 账号 ====="
kubectl get cm bk-repo-bkrepo-auth -n $NS -o yaml 2>/dev/null | sed 's/^/  /'

echo ""
echo "===== 3. 试 auth API 建用户（带 platform 头）====="
AS=10.96.211.56
kubectl exec netprobe -n $NS -- bash -c "
echo '  --- 尝试1: 带 X-DEVOPS-UID ---'
curl -s --max-time 8 -X POST 'http://$AS/service/user/create' \
  -H 'Content-Type: application/json' -H 'X-DEVOPS-UID: admin' \
  -d '{\"userId\":\"admin\",\"name\":\"admin\",\"pwd\":\"blueking\",\"admin\":true}' | head -c 300
echo ''
echo '  --- 尝试2: 查用户列表(带UID头) ---'
curl -s --max-time 8 'http://$AS/service/user/list' -H 'X-DEVOPS-UID: admin' | head -c 300
echo ''
echo '  --- 尝试3: /api/user/create 带UID头 ---'
curl -s --max-time 8 -X POST 'http://$AS/api/user/create' \
  -H 'Content-Type: application/json' -H 'X-DEVOPS-UID: admin' \
  -d '{\"userId\":\"admin\",\"name\":\"admin\",\"pwd\":\"blueking\",\"admin\":true}' | head -c 300
echo ''
" 2>&1

echo ""
echo "===== 4. 看 gateway 的日志，确认 user/create 500 的具体原因 ====="
GP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-gateway' | grep Running | awk '{print $1}' | head -1)
kubectl logs $GP -n $NS --tail=40 2>&1 | grep -iE 'user|create|error|exception' | tail -10 | cut -c1-220 | sed 's/^/  /'
