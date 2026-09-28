#!/usr/bin/env bash
set -uo pipefail
NS=blueking
BAK=$(ls -d /root/bk72/install/bk-job-backup-* 2>/dev/null | tail -1)
J=bkpaas3-apiserver-migrate-db-1

echo "===== 1. apiserver-bkrepo-init 的完整定义 ====="
python3 - "$BAK/$J.yaml" <<'PY'
import yaml,sys,json
d = yaml.safe_load(open(sys.argv[1]))
for c in d['spec']['template']['spec']['containers']:
    if c['name']=='apiserver-bkrepo-init':
        print("  command:", c.get('command'))
        print("  args:   ", c.get('args'))
        print("  envFrom:", json.dumps(c.get('envFrom'),ensure_ascii=False))
        ev=[e for e in (c.get('env') or []) if 'REPO' in e.get('name','').upper() or 'PASS' in e.get('name','').upper()]
        print("  env(REPO/PASS):", json.dumps(ev,ensure_ascii=False)[:400])
PY

echo ""
echo "===== 2. 起一个只跑 bkrepo-init 的探针（完全同参数）====="
python3 - "$BAK/$J.yaml" <<'PY'
import yaml,sys,json
d = yaml.safe_load(open(sys.argv[1]))
c=[x for x in d['spec']['template']['spec']['containers'] if x['name']=='apiserver-bkrepo-init'][0]
pod={"apiVersion":"v1","kind":"Pod","metadata":{"name":"bkrepo-init-probe","namespace":"blueking"},
 "spec":{"restartPolicy":"Never","initContainers":d['spec']['template']['spec'].get('initContainers') or [],
  "containers":[{"name":"bi","image":c['image'],"command":c.get('command'),"args":c.get('args'),
    "envFrom":c.get('envFrom') or [],"env":c.get('env') or [],
    "volumeMounts":c.get('volumeMounts') or []}],
  "volumes":d['spec']['template']['spec'].get('volumes') or []}}
json.dump(pod,open('/tmp/biprobe.json','w'))
print("  已生成 /tmp/biprobe.json")
PY
kubectl delete pod bkrepo-init-probe -n $NS --wait=false 2>/dev/null >/dev/null
kubectl apply -f /tmp/biprobe.json 2>&1 | sed 's/^/  /'

echo ""
echo "===== 3. 等它跑完（最多 240s）====="
for i in $(seq 1 80); do
  S=$(kubectl get pod bkrepo-init-probe -n $NS -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$S" = "Succeeded" ] || [ "$S" = "Failed" ] && { echo "  终态: $S"; break; }
  sleep 3
done
kubectl get pod bkrepo-init-probe -n $NS -o jsonpath='  exit={.status.containerStatuses[0].state.terminated.exitCode} reason={.status.containerStatuses[0].state.terminated.reason}{"\n"}' 2>&1

echo ""
echo "===== 4. 完整日志 ====="
kubectl logs bkrepo-init-probe -n $NS 2>&1 | grep -viE 'InsecureKey|Deprecat|warnings.warn|_jws|return self' | tail -30 | sed 's/^/    /'
