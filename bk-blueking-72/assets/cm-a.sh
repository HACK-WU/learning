#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. ConfigMap bk-gse-certs 的元数据（是否 helm 管理）====="
kubectl get cm bk-gse-certs -n blueking -o json 2>/dev/null | python3 -c '
import json,sys,hashlib,base64
d=json.load(sys.stdin)
m=d["metadata"]
print("  name:",m["name"]," ns:",m["namespace"])
print("  labels:",json.dumps(m.get("labels",{}),ensure_ascii=False))
print("  annotations keys:",list((m.get("annotations") or {}).keys())[:6])
for k,v in d.get("data",{}).items():
    print("   key:",k," len:",len(v))
    if "BEGIN" in v:
        norm="".join(l.strip() for l in v.splitlines() if "BEGIN" not in l and "END" not in l)
        print("      公钥md5:",hashlib.md5(norm.encode()).hexdigest())
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 该 ConfigMap 由哪个 helm release 拥有 ====="
helm list -n blueking 2>/dev/null | head -20 | sed 's/^/  /'
echo ""
echo "  --- 哪个 release 的 manifest 含 bk-gse-certs ---"
for r in $(helm list -n blueking --short 2>/dev/null); do
  if helm get manifest "$r" -n blueking 2>/dev/null | grep -q 'bk-gse-certs'; then
    echo "   >>> release: $r"
  fi
done

echo ""
echo "===== 3. 关键：apigw_jwt.crt 在 ConfigMap 里的 key 名 ====="
kubectl get cm bk-gse-certs -n blueking -o jsonpath='{range $k,$v := .data}{$k}{"="}{$v}{"\n"}{end}' 2>/dev/null | head -3 | cut -c1-120 | sed 's/^/  /'

echo ""
echo "===== 4. 备份当前 ConfigMap（改前存证）====="
kubectl get cm bk-gse-certs -n blueking -o yaml 2>/dev/null | head -5 | sed 's/^/  /'
echo "  (完整备份待执行时再落盘)"
} > /root/cm-a.txt 2>&1
cat /root/cm-a.txt
