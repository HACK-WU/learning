#!/usr/bin/env bash
# 修正：单条大 value 用 --data-binary @文件，避免命令行过长
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
T=/tmp/consul-ops/bigval.bin

echo "########## 1. 单条 KV value 上限 ##########"
for KB in 256 512 513 1024; do
  python3 -c "open('$T','wb').write(b'x'*($KB*1024))"
  C=$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary @"$T" "http://127.0.0.1:8501/v1/kv/limit/single$KB")
  echo "  单条 value=${KB}KB → HTTP=$C"
done
rm -f "$T"

echo
echo "########## 2. 事务总大小：精确定位（在 0.3~0.62MB 间二分）##########"
try_txn() {
python3 - "$1" "$2" <<'PYEOF'
import sys,json,urllib.request,base64
n=int(sys.argv[1]); sz=int(sys.argv[2])
val=base64.b64encode(b'x'*sz).decode()
ops=[{"KV":{"Verb":"set","Key":f"lm/{n}_{sz}/{i}","Value":val}} for i in range(n)]
tot=n*sz
try:
    r=urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8501/v1/txn",json.dumps(ops).encode(),method="PUT"),timeout=60)
    print(f"  {n:4d} x {sz:6d}B = {tot/1024:8.0f} KB → OK")
except Exception as e:
    print(f"  {n:4d} x {sz:6d}B = {tot/1024:8.0f} KB → {getattr(e,'code','ERR')} 被拒")
PYEOF
}
for n in 5 6 7 8 9 10; do try_txn $n 65536; done
echo "  --- 换小 value 复验（看是总大小还是条数限制）---"
for n in 20 40 60 80; do try_txn $n 8192; done

echo
echo "########## 3. 结论 ##########"
echo "  见上方：OK/被拒的临界点即为事务请求体上限"
