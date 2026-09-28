#!/usr/bin/env bash
set -uo pipefail
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 1. volume bk-gse-cert 的真实定义（完整 json）====="
kubectl get pod "$GP" -n blueking -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
for v in d["spec"]["volumes"]:
    if v["name"] in ("bk-gse-cert","gse-cert"):
        print("  volume:", v["name"])
        print(json.dumps(v, indent=4, ensure_ascii=False))
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. 该卷挂载后 cert 目录里有什么 ====="
kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c 'ls -la /data/gse/cert/ 2>&1' | sed 's/^/  /'

echo ""
echo "===== 3. 源头：helm 里 gse 证书怎么生成的 ====="
echo "  --- 搜 helm values 里 gse cert/jwt ---"
grep -rn -iE 'apigw_jwt|gse-cert|jwt.*crt|cert.*jwt' /root/bk72/install/blueking/ 2>/dev/null | grep -v '\.bak' | head -12 | sed 's/^/  /'

echo ""
echo "  --- gse chart 目录 ---"
ls /root/bk72/install/blueking/ 2>/dev/null | grep -i gse | sed 's/^/  /'
find /root/bk72 -maxdepth 6 -type d -name '*gse*' 2>/dev/null | head -5 | sed 's/^/  /'

echo ""
echo "===== 4. 关键结论所需：改数据库后，GSE 证书会不会自动变？ ====="
echo "  如果 /data/gse/cert/apigw_jwt.crt 来自 Secret/ConfigMap -> 不会自动变，需重建"
echo "  如果是 init 容器生成 -> 重启 pod 可重新生成"
kubectl get pod "$GP" -n blueking -o jsonpath='{range .spec.initContainers[*]}  init容器: {.name}{"\n"}{end}' 2>/dev/null | sed 's/^/  /'
} > /root/secret-c.txt 2>&1
cat /root/secret-c.txt
