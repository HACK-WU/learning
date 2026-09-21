#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops

echo "########## 1. TLS 证书：自建 CA 签发 server 证书 ##########"
cd $D/tls
openssl req -x509 -newkey rsa:2048 -days 365 -nodes \
  -keyout ca-key.pem -out ca.pem -subj "/CN=consul-ops-ca" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout server-key.pem -out server.csr \
  -subj "/CN=server.opsdc1.consul" 2>/dev/null
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -days 30 -out server.pem 2>/dev/null
echo "  签发完成，有效期 30 天"
echo "  到期日: $(openssl x509 -in server.pem -noout -enddate)"

echo
echo "########## 2. 核验：证书剩余天数怎么算（监控到期的基础）##########"
END=$(openssl x509 -in server.pem -noout -enddate | cut -d= -f2)
echo "  enddate = $END"
python3 - <<'PYEOF'
import subprocess, datetime
out = subprocess.run(['openssl','x509','-in','/tmp/consul-ops/tls/server.pem','-noout','-enddate'],
                     capture_output=True, text=True).stdout.strip()
ds = out.split('=')[1]
# 格式: Sep 19 08:00:00 2026 GMT
dt = datetime.datetime.strptime(ds, '%b %d %H:%M:%S %Y %Z')
left = (dt - datetime.datetime.utcnow()).days
print(f"  到期时刻 = {dt} UTC")
print(f"  剩余天数 = {left} 天")
print(f"  → 告警阈值常设 30 天，剩余 {left} 天 {'已触发' if left < 30 else '未触发'}")
PYEOF

echo
echo "########## 3. Connect CA 轮换实测（内置 CA，API 完成，不重启）##########"
echo "  轮换前 root 数 = $(curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["Roots"]))')"
echo "  轮换前 ActiveRootID = $(curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c 'import sys,json;print(json.load(sys.stdin)["ActiveRootID"])')"

echo "  --- 执行轮换（通过 CA 配置触发新 root）---"
curl -s -X PUT -d '{"Provider":"consul","Config":{"RotationPeriod":"2160h","IntermediateCertTTL":"8760h"}}' \
  $CONSUL_HTTP_ADDR/v1/connect/ca/configuration 2>&1 | head -c 200
echo
sleep 3
echo "  轮换后 root 数 = $(curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["Roots"]))')"

echo
echo "########## 4. gossip keyring（加密未启用时的现状）##########"
consul keyring -list 2>&1 | head -4 | sed 's/^/  /'
