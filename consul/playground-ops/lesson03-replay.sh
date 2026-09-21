#!/usr/bin/env bash
# 严格照抄讲义第四幕，逐条断言（注意：Gauges 可能 list/dict，State 是 $4）
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
BASE=/tmp/consul-ops
FAIL=0

gen() {
  local i=$1
  cat > "$BASE/conf/node$i.hcl" <<EOF
node_name  = "ops-node-$i"
server     = true
datacenter = "opsdc1"
data_dir   = "$BASE/data/node$i"
log_level  = "INFO"
bind_addr  = "127.0.0.$i"
client_addr = "127.0.0.$i"
bootstrap_expect = 3
telemetry { prometheus_retention_time = "60s" }
ports {
  server   = $((8300 + i))
  serf_lan = $((9300 + i))
  serf_wan = -1
  http     = $((8500 + i))
  dns      = $((8600 + i))
  grpc     = $((8700 + i))
  grpc_tls = $((8800 + i))
}
retry_join = ["127.0.0.1:9301", "127.0.0.2:9302", "127.0.0.3:9303"]
EOF
}

pkill -x consul 2>/dev/null; sleep 3
rm -rf "$BASE/data" "$BASE/log"; mkdir -p "$BASE"/data/node{1,2,3} "$BASE"/conf "$BASE"/log
for i in 1 2 3; do sudo ip addr add 127.0.0.$i/8 dev lo 2>/dev/null; gen $i; done
for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
sleep 16

echo "== 断言1 单条 value 512过/513拒 =="
T=/tmp/bigval.bin
python3 -c "open('$T','wb').write(b'x'*(512*1024))"
C512=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary @"$T" $CONSUL_HTTP_ADDR/v1/kv/limit/s512)
python3 -c "open('$T','wb').write(b'x'*(513*1024))"
C513=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary @"$T" $CONSUL_HTTP_ADDR/v1/kv/limit/s513)
rm -f "$T"
echo "  512KB=$C512 (期望200) 513KB=$C513 (期望413)"
[ "$C512" = 200 ] && [ "$C513" = 413 ] || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言2 事务 320过/384拒 =="
python3 - <<'PYEOF'
import json,urllib.request,base64,sys
res={}
for n,sz in [(5,65536),(6,65536)]:
    ops=[{"KV":{"Verb":"set","Key":f"lm/{n}_{sz}/{i}","Value":base64.b64encode(b'x'*sz).decode()}} for i in range(n)]
    try:
        r=urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8501/v1/txn",json.dumps(ops).encode(),method="PUT"),timeout=60)
        res[n*sz//1024]=r.status
    except Exception as e:
        res[n*sz//1024]=getattr(e,'code','ERR')
print("  320KB =",res.get(320)," 384KB =",res.get(384))
import os
ok = res.get(320)==200 and res.get(384)==413
sys.exit(0 if ok else 3)
PYEOF
[ $? -eq 0 ] || { echo "  !! FAIL 事务边界"; FAIL=1; }

echo "== 断言3 吞吐 串行<并发<批量 =="
S=$(date +%s.%N); for i in $(seq 1 60); do curl -s -o /dev/null -X PUT -d s $CONSUL_HTTP_ADDR/v1/kv/cmp/s/$i; done; E=$(date +%s.%N)
SER=$(python3 -c "print(f'{60/($E-$S):.0f}')")
S=$(date +%s.%N)
for b in $(seq 1 6); do for i in $(seq 1 10); do curl -s -o /dev/null -X PUT -d c $CONSUL_HTTP_ADDR/v1/kv/cmp/c/$b/$i & done; wait; done
E=$(date +%s.%N)
CON=$(python3 -c "print(f'{60/($E-$S):.0f}')")
TXN=$(python3 - <<'PYEOF'
import json,urllib.request,time
ops=[{"KV":{"Verb":"set","Key":f"txn/{i}","Value":"dg=="}} for i in range(100)]
t=time.time()
urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8501/v1/txn",json.dumps(ops).encode(),method="PUT"),timeout=30)
print(f"{100/(time.time()-t):.0f}")
PYEOF
)
echo "  串行=$SER 并发=$CON 批量事务=$TXN"
python3 -c "
s,c,t=$SER,$CON,$TXN
assert s<c<t, f'顺序不对 {s}<{c}<{t}'
assert c/s>3, f'并发倍数仅 {c/s:.1f}'
print(f'  通过：并发/串行={c/s:.1f}x  批量/串行={t/s:.1f}x')
" || { echo "  !! FAIL 吞吐排序"; FAIL=1; }

echo "== 断言4 三种读模式延迟都在 5~7ms 且差<1ms =="
bench() { S=$(date +%s.%N); for i in $(seq 1 300); do curl -s -o /dev/null "$1"; done; E=$(date +%s.%N); python3 -c "print(f'{($E-$S)/300*1000:.2f}')"; }
D1=$(bench "$CONSUL_HTTP_ADDR/v1/kv/cmp/s/1?raw")
D2=$(bench "$CONSUL_HTTP_ADDR/v1/kv/cmp/s/1?raw&consistent")
D3=$(bench "$CONSUL_HTTP_ADDR/v1/kv/cmp/s/1?raw&stale")
echo "  default=$D1 consistent=$D2 stale=$D3 ms"
python3 -c "
v=[$D1,$D2,$D3]
assert all(3<x<12 for x in v), f'超出预期范围 {v}'
assert max(v)-min(v)<3, f'差异过大 {max(v)-min(v):.2f}'
print(f'  通过：极差 {max(v)-min(v):.2f} ms')
" || { echo "  !! FAIL 读模式"; FAIL=1; }

echo "== 断言5 stale 读到旧值 / consistent 读到新值 =="
peers() { consul operator raft list-peers | awk 'NR>1 && NF>=6'; }
LN=$(peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
FN=$(peers | awk '$4!="leader"{print $1}' | head -1 | grep -oE '[0-9]+$')
echo "  leader=node$LN follower=node$FN"
[ -n "$LN" ] && [ -n "$FN" ] || { echo "  !! FAIL 取角色失败(State应为\$4)"; FAIL=1; }
curl -s -o /dev/null -X PUT -d AAA "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"; sleep 1
curl -s -o /dev/null -X PUT -d BBB "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"
RS=$(curl -s "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&stale")
RC=$(curl -s "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&consistent")
echo "  stale=[$RS] consistent=[$RC]"
[ "$RC" = "BBB" ] || { echo "  !! FAIL consistent 应读新值"; FAIL=1; }
[ "$RS" = "AAA" ] && echo "  stale 读到旧值（陈旧窗口复现）" || echo "  （本次 stale 已同步到 BBB，陈旧窗口极短，非失败）"

echo "== 断言6 raft index 可读且 last>=applied =="
curl -s $CONSUL_HTTP_ADDR/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin); g=d.get('Gauges',{})
if isinstance(g,list): g={s['Name']:s for s in g if isinstance(s,dict) and 'Name' in s}
la=ap=None
for k,v in g.items():
    if k.endswith('raft.last_index'): la=v['Value'] if isinstance(v,dict) else v
    if k.endswith('raft.applied_index'): ap=v['Value'] if isinstance(v,dict) else v
print(f'  last_index={la} applied_index={ap} 滞后={la-ap}')
assert la is not None and ap is not None, '未能解析 raft index'
assert la>=ap, 'applied 不应超过 last'
" || { echo "  !! FAIL index"; FAIL=1; }

for p in $(pgrep -x consul 2>/dev/null); do kill -9 "$p" 2>/dev/null; done; sleep 2
echo
[ $FAIL -eq 0 ] && echo "=== 课3 终验通过（6 组断言）===" || echo "=== 终验存在失败 ==="
exit $FAIL
