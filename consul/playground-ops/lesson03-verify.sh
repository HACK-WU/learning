#!/usr/bin/env bash
# 课3 终验（集群已由 lesson03-start.sh 建好，本脚本只做断言）
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
FAIL=0
echo "前置检查: 进程=$(pgrep -x consul | wc -l)"
consul operator raft list-peers 2>&1 | head -4

echo
echo "== 断言1 单条 value 512过/513拒 =="
T=/tmp/bigval.bin
python3 -c "open('$T','wb').write(b'x'*(512*1024))"
C512=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary @"$T" $CONSUL_HTTP_ADDR/v1/kv/limit/s512)
python3 -c "open('$T','wb').write(b'x'*(513*1024))"
C513=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary @"$T" $CONSUL_HTTP_ADDR/v1/kv/limit/s513)
rm -f "$T"
echo "  512KB=$C512 (期望200)  513KB=$C513 (期望413)"
[ "$C512" = 200 ] && [ "$C513" = 413 ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言2 事务 320KB过/384KB拒 =="
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
print(f"  320KB={res.get(320)} (期望200)  384KB={res.get(384)} (期望413)")
sys.exit(0 if res.get(320)==200 and res.get(384)==413 else 3)
PYEOF
[ $? -eq 0 ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言3 吞吐：串行 < 并发 < 批量事务 =="
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
echo "  串行=$SER  并发=$CON  批量事务=$TXN"
python3 -c "
s,c,t=$SER,$CON,$TXN
assert s<c<t, f'排序不对 {s}<{c}<{t}'
assert c/s>3, f'并发倍数仅 {c/s:.1f}'
assert t/s>10, f'批量倍数仅 {t/s:.1f}'
print(f'  通过：并发={c/s:.1f}x  批量={t/s:.1f}x')
" && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言4 三种读模式：延迟接近 =="
bench() { S=$(date +%s.%N); for i in $(seq 1 300); do curl -s -o /dev/null "$1"; done; E=$(date +%s.%N); python3 -c "print(f'{($E-$S)/300*1000:.2f}')"; }
D1=$(bench "$CONSUL_HTTP_ADDR/v1/kv/cmp/s/1?raw")
D2=$(bench "$CONSUL_HTTP_ADDR/v1/kv/cmp/s/1?raw&consistent")
D3=$(bench "$CONSUL_HTTP_ADDR/v1/kv/cmp/s/1?raw&stale")
echo "  default=$D1  consistent=$D2  stale=$D3 ms"
python3 -c "
v=[$D1,$D2,$D3]
assert all(2<x<15 for x in v), f'超范围 {v}'
assert max(v)-min(v)<3, f'极差过大 {max(v)-min(v):.2f}'
print(f'  通过：极差 {max(v)-min(v):.2f} ms')
" || { echo "  !! FAIL"; FAIL=1; }

echo "== 断言5 stale 陈旧窗口 / consistent 新值 =="
peers() { consul operator raft list-peers 2>/dev/null | awk 'NR>1 && NF>=6'; }
LN=$(peers | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
FN=$(peers | awk '$4!="leader"{print $1}' | head -1 | grep -oE '[0-9]+$')
echo "  leader=node$LN  follower=node$FN"
if [ -z "$LN" ] || [ -z "$FN" ]; then echo "  !! FAIL 角色提取(State 应为 \$4)"; FAIL=1; else
  curl -s -o /dev/null -X PUT -d AAA "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"; sleep 1
  curl -s -o /dev/null -X PUT -d BBB "http://127.0.0.$LN:$((8500+LN))/v1/kv/lag/p"
  RC=$(curl -s "http://127.0.0.$FN:$((8500+FN))/v1/kv/lag/p?raw&consistent")
  echo "  consistent=[$RC] (期望 BBB)"
  [ "$RC" = "BBB" ] && echo "  通过" || { echo "  !! FAIL"; FAIL=1; }
  echo "  （stale 可能已同步，陈旧窗口极短，不作硬断言）"
fi

echo "== 断言6 raft index 可读 =="
curl -s $CONSUL_HTTP_ADDR/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin); g=d.get('Gauges',{})
if isinstance(g,list): g={s['Name']:s for s in g if isinstance(s,dict) and 'Name' in s}
la=ap=None
for k,v in g.items():
    if k.endswith('raft.last_index'): la=v['Value'] if isinstance(v,dict) else v
    if k.endswith('raft.applied_index'): ap=v['Value'] if isinstance(v,dict) else v
assert la is not None and ap is not None, '解析失败'
assert la>=ap
print(f'  last_index={la} applied_index={ap} 滞后={la-ap}  通过')
" || { echo "  !! FAIL index"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "=== 课3 终验通过（6 组断言）===" || echo "=== 终验存在失败 ==="
exit $FAIL
