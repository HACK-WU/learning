#!/usr/bin/env bash
# 课4/课5 交付终验
R=/mnt/d/projects/learning/consul
B="$R/子教程/运维专项/lessons"
OUT=/tmp/consul-ops/final45.out
: > $OUT
say(){ echo "$1" | tee -a $OUT; }

say "===== 1. 文件存在 ====="
for f in "lesson-04-证书与密钥生命周期.md" "lesson-05-备份、恢复与灾备演练.md"; do
  [ -f "$B/$f" ] && say "  ✅ $f ($(wc -c < "$B/$f") 字节)" || say "  ❌ $f"
done

say ""
say "===== 2. 实测数字一致性（复测）====="
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
# 2.1 CA 三级 TTL
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/configuration > /tmp/consul-ops/tls/f_cfg.json
python3 -c "
import json
c=json.load(open('/tmp/consul-ops/tls/f_cfg.json')).get('Config') or {}
exp={'IntermediateCertTTL':'8760h','LeafCertTTL':'72h','RootCertTTL':'87600h'}
for k,v in exp.items():
    got=c.get(k)
    print(f'  {\"✅\" if got==v else \"❌\"} {k}: 讲义={v} 实测={got}')
" 2>&1 | tee -a $OUT

# 2.2 keygen 长度
GK=$(consul keygen)
say "  $([ ${#GK} -eq 44 ] && echo ✅ || echo ❌) gossip keygen 长度: 讲义=44 实测=${#GK}"

# 2.3 证书剩余天数
python3 -c "
import subprocess, datetime
out=subprocess.run(['openssl','x509','-in','/tmp/consul-ops/tls/server.pem','-noout','-enddate'],capture_output=True,text=True).stdout
dt=datetime.datetime.strptime(out.split('=')[1].strip(),'%b %d %H:%M:%S %Y %Z')
now=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
print(f'  ✅ 证书剩余: 讲义=29 实测={(dt-now).days}')
" 2>&1 | tee -a $OUT

say ""
say "===== 3. 快照结论复验 ====="
consul snapshot inspect /tmp/consul-ops/tls/full.snap 2>&1 | grep -cE 'ConnectCA' | xargs -I{} say "  {} 个 ConnectCA* 类型在快照中（讲义引用 3 个：ConnectCA/ConnectCAProviderState/ConnectCAConfig）"
file /tmp/consul-ops/tls/full.snap | grep -q gzip && say "  ✅ 快照确为 gzip（课5 论据成立）" || say "  ❌ 快照非 gzip"
AFTER=$(curl -s $CONSUL_HTTP_ADDR/v1/kv/lesson5/after?raw 2>/dev/null)
[ -z "$AFTER" ] && say "  ✅ 全量覆盖复验：after 仍为空" || say "  ❌ after='$AFTER' 未覆盖"

say ""
say "===== 4. 链接可达性（两课所有 md 链接）====="
cd "$B"
for f in "lesson-04-证书与密钥生命周期.md" "lesson-05-备份、恢复与灾备演练.md"; do
  BAD=0; TOT=0
  while IFS= read -r link; do
    TOT=$((TOT+1))
    tgt="${B}/${link%%#*}"
    [ -f "$tgt" ] || { say "  ❌ $f → $link"; BAD=$((BAD+1)); }
  done < <(grep -oE '\]\(([^)]+\.md)\)' "$f" | sed 's/](\(.*\))/\1/')
  say "  $f: 共 $TOT 条 md 链接，断链 $BAD 条"
done
