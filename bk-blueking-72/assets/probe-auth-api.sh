#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 直连 auth svc 探测 API ====="
AS=$(kubectl get svc bk-repo-bkrepo-auth -n $NS -o jsonpath='{.spec.clusterIP}')
echo "  auth svc = $AS"
kubectl exec netprobe -n $NS -- bash -c "
for p in /api/user/create /auth/api/user/create /service/user/create /api/user/add /user/create; do
  C=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 -X POST http://$AS\$p)
  echo \"    POST \$p -> \$C\"
done
for p in /api/user/list /service/user/list /api/user; do
  C=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 http://$AS\$p)
  echo \"    GET  \$p -> \$C\"
done
" 2>&1

echo ""
echo "===== 2. 看 auth 镜像里的初始化脚本/默认数据 ====="
AP=$(kubectl get pods -n $NS --no-headers 2>/dev/null | grep 'bkrepo-auth' | grep Running | awk '{print $1}' | head -1)
kubectl exec $AP -n $NS -- bash -c "ls /data/ 2>/dev/null; ls /data/*/ 2>/dev/null | head -20" 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 查 bkrepo gateway 的路由表（user 相关端点）====="
kubectl exec netprobe -n $NS -- bash -c "curl -s --max-time 8 http://bk-repo-bkrepo-gateway/actuator/gateway/routes 2>/dev/null | head -c 600" 2>&1 | sed 's/^/  /'
echo ""

echo "===== 4. 关键：bkrepo 官方文档的初始化方式 —— 找 chart 里的 init job 模板 ====="
kubectl get secret sh.helm.release.v1.bk-repo.v1 -n $NS -o jsonpath='{.data.release}' 2>/dev/null | base64 -d 2>/dev/null | base64 -d 2>/dev/null | python3 -c "
import sys,gzip,json,re
raw=sys.stdin.buffer.read()
data=raw
try: data=gzip.decompress(raw)
except Exception: pass
try:
    j=json.loads(data)
    # chart 的 templates 里找 init
    ch=j.get('chart',{})
    tpl=ch.get('metadata',{}).get('name','')
    print('  chart:',tpl, ch.get('metadata',{}).get('version',''))
    files=[]
    for f in ch.get('files',[]) or []:
        files.append(f.get('name',''))
    for f in ch.get('templates',[]) or []:
        files.append(f.get('name',''))
    print('  模板文件:', [x for x in files if x][:40])
    # 找 init 相关
    for f in (ch.get('templates',[]) or []) + (ch.get('files',[]) or []):
        nm=f.get('name','')
        if re.search(r'(?i)init|job|data', nm):
            print('  >>', nm)
except Exception as e:
    print('  解析失败:', e)
" 2>&1

echo ""
echo "===== 5. 尝试 auth 的 swagger/API 列表 ====="
kubectl exec netprobe -n $NS -- bash -c "
for p in /v3/api-docs /swagger-ui.html /api-docs; do
  echo \"    \$p -> \$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 http://$AS\$p)\"
done
curl -s --max-time 8 http://$AS/v3/api-docs 2>/dev/null | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin)
    ps=[p for p in d.get(\"paths\",{}) if \"user\" in p.lower()]
    print(\"    user 相关路径:\", ps[:20])
except Exception as e: print(\"    \", e)
'" 2>&1
