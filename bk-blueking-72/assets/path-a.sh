#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 1. monitor 调 GSE 的入口配置（ESB vs apigateway）====="
kubectl get cm bk-monitor-monitor-env -n blueking -o jsonpath='{.data}' 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin)
    for k,v in d.items():
        if any(x in k.upper() for x in ["GSE","BKAPI","APIGW","ESB","HOST"]):
            print("  %s = %s" % (k, str(v)[:90]))
except Exception as e: print("  err:",e)
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 2. generate_rsa_keypair.sh（密钥怎么生成的）====="
cat /root/bk72/install/blueking/scripts/generate_rsa_keypair.sh 2>/dev/null | head -45 | sed 's/^/  /'

echo ""
echo "===== 3. bkapigateway_builtin_keypair.yaml 里 bk-gse 与 ESB 的关系 ====="
head -30 /root/bk72/install/blueking/environments/default/bkapigateway_builtin_keypair.yaml 2>/dev/null | cut -c1-100 | sed 's/^/  /'
} > /root/path-a.txt 2>&1
cat /root/path-a.txt
