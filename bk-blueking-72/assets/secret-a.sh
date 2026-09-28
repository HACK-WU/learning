#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. secret bk-gse-certs 的结构 ====="
kubectl get secret bk-gse-certs -n blueking -o json 2>/dev/null | python3 -c '
import json,sys,hashlib
try:
    d=json.load(sys.stdin)
    print("  secret:", d["metadata"]["name"])
    print("  labels:", d["metadata"].get("labels"))
    for k,v in d.get("data",{}).items():
        import base64
        raw=base64.b64decode(v)
        print("   key:", k, " 字节:", len(raw))
        if b"BEGIN" in raw or b"KEY" in raw:
            norm=b"".join(l.strip() for l in raw.splitlines() if b"BEGIN" not in l and b"END" not in l)
            print("      公钥md5:", hashlib.md5(norm).hexdigest())
except Exception as e:
    print("  err:",e)
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 该 secret 由谁创建（helm 管理？）====="
kubectl get secret bk-gse-certs -n blueking -o jsonpath='{.metadata.annotations}' 2>/dev/null | sed 's/^/  /'
echo ""
kubectl get secret bk-gse-certs -n blueking -o jsonpath='{.metadata.labels}' 2>/dev/null | sed 's/^/  /'
echo ""

echo ""
echo "===== 3. helm 里 gse cert 的定义（找到真正的源头）====="
ls /root/bk72/install/blueking/ 2>/dev/null | head -20 | sed 's/^/  /'
echo "  --- 搜 bk-gse-certs 定义 ---"
grep -rn 'bk-gse-certs\|apigw_jwt' /root/bk72/install/blueking/ 2>/dev/null | head -15 | sed 's/^/  /'

echo ""
echo "===== 4. GSE 哪些 pod 挂了这个 secret（要重启的范围）====="
for p in $(kubectl get pods -n blueking --no-headers 2>/dev/null | awk '{print $1}'); do
  if kubectl get pod "$p" -n blueking -o json 2>/dev/null | grep -q 'bk-gse-certs'; then
    echo "   $p"
  fi
done
} > /root/secret-a.txt 2>&1
cat /root/secret-a.txt
