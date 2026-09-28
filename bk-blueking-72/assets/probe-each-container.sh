#!/usr/bin/env bash
set -uo pipefail
NS=blueking
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. 从备份提取 3 个 main 容器的命令 ====="
python3 - "$BAK/$J.yaml" <<'PY'
import yaml,sys
d = yaml.safe_load(open(sys.argv[1]))
for c in d['spec']['template']['spec']['containers']:
    print(f"  [{c['name']}]")
    print(f"     image: {c.get('image')}")
    print(f"     cmd:   {c.get('command')}")
    print(f"     args:  {c.get('args')}")
    ef = c.get('envFrom') or []
    print(f"     envFrom: {[list(x.keys())[0] for x in ef]}")
PY

echo ""
echo "===== 2. 在探针 Pod 里逐个模拟 ====="
echo "  --- 容器2: workloads-db-migrate ---"
kubectl exec paas3-mig-probe -n $NS -- bash -c 'cd /app && python manage.py migrate --no-input 2>&1 | tail -6' 2>&1 | grep -viE 'InsecureKey|Deprecat|warn' | sed 's/^/    /'

echo ""
echo "  --- 容器3: apiserver-bkrepo-init（重点嫌疑）---"
kubectl exec paas3-mig-probe -n $NS -- bash -c 'cd /app && python manage.py init_bkrepo --dry-run true --init-enabled true --super-username admin --super-password blueking --bkpaas3-username bkpaas3 --bkpaas3-password blueking --addons-username addons --addons-password blueking --lesscode-username lesscode --lesscode-password blueking 2>&1 | tail -8' 2>&1 | grep -viE 'InsecureKey|Deprecat|warn' | sed 's/^/    /'

echo ""
echo "===== 3. 关键：bkrepo 现在能不能访问 ====="
kubectl exec paas3-mig-probe -n $NS -- env 2>/dev/null | grep -iE 'BKREPO' | head -8 | sed 's/^/    /'
echo ""
echo "  bkrepo 域名连通性:"
for d in bkrepo.example.com static.bkrepo.example.com docker.paas.example.com; do
  C=$(kubectl exec paas3-mig-probe -n $NS -- bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://$d/" 2>/dev/null)
  echo "    ${C:-000}  $d"
done

echo ""
echo "===== 4. init_bkrepo 真跑（非 dry-run）会不会失败 ====="
echo "  （先不真跑，看 dry-run 是否 OK；上面 dry-run 已"初始化成功"）"

echo ""
echo "===== 5. 看 Job 里 bkrepo-init 的真实参数（从备份）====="
python3 - "$BAK/$J.yaml" <<'PY'
import yaml,sys
d = yaml.safe_load(open(sys.argv[1]))
for c in d['spec']['template']['spec']['containers']:
    if 'bkrepo' in c['name']:
        print("    ", c.get('command'), c.get('args'))
PY
