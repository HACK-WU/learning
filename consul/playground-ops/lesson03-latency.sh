#!/usr/bin/env bash
# 修正：Gauges 可能是 list。用 robust 解析取 raft index
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

idx() {
  curl -s "$1/v1/agent/metrics" | python3 -c "
import sys,json
d=json.load(sys.stdin)
def flat(o):
    if isinstance(o,dict): return o
    if isinstance(o,list):
        r={}
        for s in o:
            if isinstance(s,dict) and 'Name' in s: r[s['Name']]=s
        return r
    return {}
g=flat(d.get('Gauges'))
def get(suf):
    for k,v in g.items():
        if k.endswith(suf):
            return v.get('Value') if isinstance(v,dict) else v
    return -1
print(get('raft.last_index'), get('raft.applied_index'))
"
}

echo "########## 1. 静息态 ##########"
for n in 1 2 3; do
  read l a < <(idx "http://127.0.0.$n:$((8500+n))")
  echo "  node$n: last=$l applied=$a 滞后=$((l-a))"
done

echo
echo "########## 2. 写入 200 条后再看 ##########"
for i in $(seq 1 200); do curl -s -o /dev/null -X PUT -d p "http://127.0.0.1:8501/v1/kv/idxx/$i"; done
sleep 2
for n in 1 2 3; do
  read l a < <(idx "http://127.0.0.$n:$((8500+n))")
  echo "  node$n: last=$l applied=$a 滞后=$((l-a))"
done

echo
echo "########## 3. 串行 vs 并发（重复 2 轮取稳定值）##########"
for round in 1 2; do
  S=$(date +%s.%N); for i in $(seq 1 60); do curl -s -o /dev/null -X PUT -d s "http://127.0.0.1:8501/v1/kv/cmp2/s$round/$i"; done; E=$(date +%s.%N)
  SER=$(python3 -c "print(f'{60/($E-$S):.0f}')")
  S=$(date +%s.%N)
  for b in $(seq 1 6); do for i in $(seq 1 10); do curl -s -o /dev/null -X PUT -d c "http://127.0.0.1:8501/v1/kv/cmp2/c$round/$b/$i" & done; wait; done
  E=$(date +%s.%N)
  CON=$(python3 -c "print(f'{60/($E-$S):.0f}')")
  echo "  第$round 轮: 串行=$SER 条/秒  并发=$CON 条/秒  倍数=$(python3 -c "print(f'{$CON/$SER:.1f}')")"
done

echo
echo "########## 4. 批量事务（txn）吞吐：1 个请求写 500 条 ##########"
python3 - <<'PYEOF'
import json,urllib.request,time
for n in (100,500):
    ops=[{"KV":{"Verb":"set","Key":f"txn/{n}/{i}","Value":"dg=="}} for i in range(n)]
    body=json.dumps(ops).encode()
    t=time.time()
    req=urllib.request.Request("http://127.0.0.1:8501/v1/txn",data=body,method="PUT")
    r=urllib.request.urlopen(req,timeout=60)
    d=time.time()-t
    print(f"  1 个事务写 {n:4d} 条: {d:.3f}s → {n/d:.0f} 条/秒")
PYEOF

echo
echo "########## 5. 大 value 对并发吞吐的影响 ##########"
for SZ in 1024 10240 65536; do
python3 - "$SZ" <<'PYEOF'
import sys,urllib.request,time,base64,json
sz=int(sys.argv[1])
val=base64.b64encode(b'x'*sz).decode()
ops=[{"KV":{"Verb":"set","Key":f"big/{sz}/{i}","Value":val}} for i in range(20)]
body=json.dumps(ops).encode()
t=time.time()
req=urllib.request.Request("http://127.0.0.1:8501/v1/txn",data=body,method="PUT")
urllib.request.urlopen(req,timeout=120)
d=time.time()-t
print(f"  value={sz:6d}B: 20 条事务写 {d:.3f}s → {20/d:.0f} 条/秒 ({(sz*20/d)/1024:.0f} KB/s)")
PYEOF
done
