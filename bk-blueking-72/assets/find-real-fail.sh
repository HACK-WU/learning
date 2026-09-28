#!/usr/bin/env bash
set -uo pipefail
NS=blueking

echo "===== 1. 找真正跑 init_bkrepo 的 Job ====="
for f in $(ls /root/bk72/install/bk-job-backup-*/bkpaas3*.yaml 2>/dev/null); do
  n=$(basename $f .yaml)
  cmd=$(python3 -c "
import yaml,sys
try:
    d=yaml.safe_load(open('$f'))
    c=d['spec']['template']['spec']['containers'][0]
    print(' '.join((c.get('args') or []) )[:120])
except Exception as e: print('?')
" 2>/dev/null)
  case "$cmd" in *init_bkrepo*) echo "  ★ $n"; echo "      $cmd";; esac
done

echo ""
echo "===== 2. 所有 paas3 相关 Job 的实际命令 ====="
for f in $(ls /root/bk72/install/bk-job-backup-*/bkpaas3*.yaml 2>/dev/null); do
  n=$(basename $f .yaml)
  python3 -c "
import yaml
d=yaml.safe_load(open('$f'))
c=d['spec']['template']['spec']['containers'][0]
a=' '.join(c.get('args') or [])
print('  %-44s %s' % ('$n'[:44], a[:95]))
" 2>/dev/null
done

echo ""
echo "===== 3. 在诊断 Pod 里手动跑 migrate，看真实结果 ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'python manage.py migrate --no-input 2>&1 | tail -12; echo "=== EXIT: $? ==="' 2>&1 | sed 's/^/    /'

echo ""
echo "===== 4. 带完整参数跑 init_bkrepo --dry-run true ====="
kubectl exec paas3-dbg -n $NS -- bash -c 'python manage.py init_bkrepo --dry-run true --init-enabled true --super-username admin --super-password blueking --bkpaas3-username bkpaas3 --bkpaas3-password blueking --addons-username addons --addons-password blueking --lesscode-username lesscode --lesscode-password blueking 2>&1 | tail -20; echo "=== EXIT: $? ==="' 2>&1 | sed 's/^/    /'
