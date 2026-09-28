#!/usr/bin/env bash
# 最可靠：用原 Job 的镜像+env 起一个 sleep Pod，进去手动跑命令看真实报错
set -uo pipefail
NS=blueking
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. 从备份提取镜像和 env 引用 ====="
python3 - "$BAK/$J.yaml" <<'PY'
import yaml,sys,json
d = yaml.safe_load(open(sys.argv[1]))
c = d['spec']['template']['spec']['containers'][0]
print("  镜像:", c.get('image'))
print("  command:", json.dumps(c.get('command'), ensure_ascii=False))
print("  args:", json.dumps(c.get('args'), ensure_ascii=False))
print("  envFrom:", json.dumps(c.get('envFrom'), ensure_ascii=False))
open('/tmp/probe-meta.txt','w').write(json.dumps({
    'image': c.get('image'),
    'command': c.get('command'),
    'args': c.get('args'),
    'envFrom': c.get('envFrom'),
    'env': c.get('env'),
    'volumeMounts': c.get('volumeMounts'),
    'volumes': d['spec']['template']['spec'].get('volumes'),
}, ensure_ascii=False))
PY

echo ""
echo "===== 2. 生成诊断 Pod（sleep 3600，进去手动跑）====="
python3 - <<'PY'
import json
meta = json.load(open('/tmp/probe-meta.txt'))
pod = {
  "apiVersion": "v1", "kind": "Pod",
  "metadata": {"name": "paas3-dbg", "namespace": "blueking"},
  "spec": {
    "restartPolicy": "Never",
    "containers": [{
      "name": "dbg",
      "image": meta['image'],
      "command": ["sleep", "3600"],
      "envFrom": meta.get('envFrom') or [],
      "env": meta.get('env') or [],
      "volumeMounts": meta.get('volumeMounts') or [],
    }],
    "volumes": meta.get('volumes') or [],
  }
}
json.dump(pod, open('/tmp/probe-pod.json','w'))
print("  已生成 /tmp/probe-pod.json")
PY

kubectl delete pod paas3-dbg -n $NS --wait=false 2>/dev/null >/dev/null
kubectl apply -f /tmp/probe-pod.json 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 等 Pod Running（最多 120s）====="
for i in $(seq 1 24); do
  S=$(kubectl get pod paas3-dbg -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Running" ] && { echo "  Running ($((i*5))s)"; break; }
  sleep 5
done
kubectl get pod paas3-dbg -n $NS --no-headers 2>/dev/null | awk '{printf "  %-16s %-12s\n", $1, $3}'

echo ""
echo "===== 4. 手动跑 init_bkrepo（真实报错）====="
kubectl exec paas3-dbg -n $NS -- bash -c 'cd /app 2>/dev/null || cd /; python manage.py init_bkrepo --dry-run 2>&1 | tail -30' 2>&1 | sed 's/^/    /'
