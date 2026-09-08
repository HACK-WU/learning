#!/usr/bin/env bash
# 决定性：无 replica 标签时，dedup 合并的代价到底是什么？
# 假设：dedup 合并后，值在两个副本之间"跳来跳去"
set -u
echo "=== 观察：无 replica（dedup 合并）后端上，同一条序列的值是否稳定 ==="
echo "   连续采样 10 次（间隔 3s），看值会不会在两个副本的值之间跳变"
echo
echo "   先记录两个副本各自的当前值作为参考："
R1=$(curl -s -G "http://localhost:19118/api/v1/query" --data-urlencode 'query=l8_card_balance{idx="0001"}' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
R2=$(curl -s -G "http://localhost:19119/api/v1/query" --data-urlencode 'query=l8_card_balance{idx="0001"}' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
echo "     norep-1 本地值 = $R1"
echo "     norep-2 本地值 = $R2"
echo

echo "   --- 后端（dedup 合并后）连续采样 ---"
for i in $(seq 1 10); do
  V=$(curl -s -G "http://localhost:19117/api/v1/query" --data-urlencode 'query=l8_card_balance{idx="0001"}' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
  echo "     #$i  后端值 = $V"
  sleep 3
done

echo
echo "=== 关键：dedup 到底保留了哪个副本的值？ ==="
echo "   VM dedup 语义：同一时间戳的重复样本，保留**最后写入**的那个（或按内部规则）"
echo "   -> 这意味着：查询结果取决于两个副本的写入顺序，而写入顺序是不确定的"
echo
echo "=== 决定性对照：有 replica 标签时，值是确定的 ==="
for i in 1 2 3; do
  V1=$(curl -s -G "http://localhost:19115/api/v1/query" --data-urlencode 'query=l8_card_balance{idx="0001",replica="1"}' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
  V2=$(curl -s -G "http://localhost:19115/api/v1/query" --data-urlencode 'query=l8_card_balance{idx="0001",replica="2"}' | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
  echo "     #$i  replica=1 -> $V1   replica=2 -> $V2"
  sleep 3
done
echo
echo "   -> 有 replica：你能明确指定用哪个副本，也能用 max/avg without(replica) 得到确定值"
echo "   -> 无 replica：你只能拿到'某个副本'的值，且是哪个不确定"
