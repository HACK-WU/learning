#!/usr/bin/env bash
set -uo pipefail
DP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'apigateway-dashboard-' | grep Running | awk '{print $1}' | head -1)
{
echo "===== 最后确认：apigateway 侧 bk-gse 密钥是否可用（决定方案A风险）====="
kubectl exec "$DP" -n blueking -- sh -c '
cd /app && python 2>&1 <<PY | tail -25
import os,sys,hashlib,datetime
sys.path.insert(0,"/app")
os.environ["DJANGO_SETTINGS_MODULE"]="apigateway.conf.default"
import django
django.setup()
from apigateway.core.models import Gateway
from apigateway.core.models import JWT as JWTModel
from apigateway.utils.crypto import KeyGenerator

g=Gateway.objects.get(name="bk-gse")
j=JWTModel.objects.filter(gateway=g).first()
print("  encrypted_private_key len =", len(j.encrypted_private_key or ""))

# 试项目内解密函数
import inspect
from apigateway.utils import crypto
print("  crypto 模块可用函数:")
for n,o in inspect.getmembers(crypto):
    if inspect.isfunction(o) or inspect.isclass(o):
        print("    -", n)

# 尝试常见解密入口
for fn in ["decrypt_private_key","get_private_key","load_private_key"]:
    f=getattr(crypto, fn, None)
    if callable(f):
        try:
            r=f(j.encrypted_private_key)
            print("  ✅",fn,"-> len",len(r) if r else 0)
        except Exception as e:
            print("  ",fn,"err:",type(e).__name__,str(e)[:60])
PY
' 2>&1 | sed 's/^/  /'

echo ""
echo "===== 结论性判断依据 ====="
echo "  已确凿事实："
echo "  1. apigateway bk-gse gateway 有 6 个 backend 直连 GSE + 41 个 resource"
echo "  2. 该 gateway 的公钥 = GSE 证书公钥 = 0e18be8a"
echo "  3. ESB 用自己密钥 0e82d670 签，与 GSE 证书不符"
echo "  4. bk-gse 的 private_key 字段为空，私钥加密存在 encrypted_private_key(len=3430)"
echo ""
echo "  => 若把 GSE 证书换成 ESB 公钥(0e82d670)："
echo "     路径1 (apigateway->GSE, 41个resource) 会立刻失效"
echo "     路径2 (ESB->GSE) 才修好"
echo "     => 方案A 是「拆东墙补西墙」，不是净收益，除非路径1本就无用"
} > /root/final-risk.txt 2>&1
cat /root/final-risk.txt
