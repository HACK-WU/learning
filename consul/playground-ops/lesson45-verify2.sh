#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
echo "===== 补测 A：keyring 现状 ====="
consul keyring -list 2>&1 | sed 's/^/  /' | head -6

echo
echo "===== 补测 B：CA 配置（RotationPeriod / IntermediateCertTTL）====="
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/configuration > $D/tls/cfg.json 2>&1
cat $D/tls/cfg.json | sed 's/^/  /'
echo

echo
echo "===== 补测 C：证书剩余天数（讲义引用 29 天，重算一次）====="
python3 -c "
import subprocess, datetime
out = subprocess.run(['openssl','x509','-in','$D/tls/server.pem','-noout','-enddate'],
                     capture_output=True, text=True).stdout.strip()
ds = out.split('=')[1]
dt = datetime.datetime.strptime(ds, '%b %d %H:%M:%S %Y %Z')
now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
left = (dt - now).days
print(f'  到期 = {dt} UTC, 剩余 = {left} 天')
"

echo
echo "===== 补测 D：确认 server.pem 有效期是 30 天签的 ====="
openssl x509 -in $D/tls/server.pem -noout -subject -enddate 2>&1 | sed 's/^/  /'
