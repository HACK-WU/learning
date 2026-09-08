#!/usr/bin/env bash
# 课 8 讲义命令逐字复验（第四幕步骤 2-7）
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1 (=$2)"; else no "$1 (期望=$3 实际=$2)"; fi; }

q(){  # q <port> <expr>
  curl -s -G "http://localhost:$1/api/v1/query" --data-urlencode "query=$2"
}
n(){  # n <port> <expr>  -> 取第一个值
  curl -s -G "http://localhost:$1/api/v1/query" --data-urlencode "query=$2" \
    | python3 -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else '0')" 2>/dev/null
}

echo "=== S2.1: 联邦端点返回序列数 ==="
F=$(curl -s -G 'http://localhost:19110/federate' --data-urlencode 'match[]={__name__=~"l8_.*"}' | grep -c '^l8_')
chk "federate 返回 l8_ 样本数" "$F" "506"

echo "=== S2.2: 联邦只传当前值（两次请求时间戳不同） ==="
T1=$(curl -s -G 'http://localhost:19110/federate' --data-urlencode 'match[]={__name__="l8_card_balance",idx="0001"}' | awk '{print $NF}')
sleep 6
T2=$(curl -s -G 'http://localhost:19110/federate' --data-urlencode 'match[]={__name__="l8_card_balance",idx="0001"}' | awk '{print $NF}')
echo "  时间戳1=$T1  时间戳2=$T2"
[ "$T1" != "$T2" ] && ok "S2.2 两次请求时间戳不同" || no "S2.2 时间戳相同"

echo "=== S2.3: 全局节点按 cluster 分组 ==="
A=$(n 19114 'count(l8_card_balance{cluster="leaf-a"})')
B=$(n 19114 'count(l8_card_balance{cluster="leaf-b"})')
chk "cluster=leaf-a 条数" "$A" "500"
chk "cluster=leaf-b 条数" "$B" "500"

echo "=== S2.4: 联邦不搬历史 ==="
H=$(curl -s -G 'http://localhost:19114/api/v1/query_range' \
  --data-urlencode 'query=l8_card_balance{idx="0001",cluster="leaf-a"}' \
  --data-urlencode "start=$(($(date +%s) - 3600))" \
  --data-urlencode "end=$(($(date +%s) - 1800))" \
  --data-urlencode 'step=60s' | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['data']['result']))")
chk "查 1 小时前命中序列数" "$H" "0"

echo "=== S2.5: TYPE=untyped 但 rate 能算 ==="
TY=$(curl -s -G 'http://localhost:19110/federate' --data-urlencode 'match[]={__name__="l8_requests_total"}' | grep '# TYPE' | head -n 1)
echo "  $TY"
echo "$TY" | grep -q 'untyped' && ok "S2.5 TYPE 为 untyped" || no "S2.5 TYPE"
LR=$(n 19110 'rate(l8_requests_total{method="GET"}[2m])')
GR=$(n 19114 'rate(l8_requests_total{method="GET",cluster="leaf-a"}[2m])')
echo "  叶子 rate=$LR  全局 rate=$GR"
[ "$LR" = "$GR" ] && ok "S2.5 叶子与全局 rate 一致" || no "S2.5 rate 不一致"

echo "=== S3: honor_labels 对照 ==="
HJ=$(curl -s -G 'http://localhost:19114/api/v1/query' --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(','.join(sorted({s['metric'].get('job','') for s in d['data']['result']})))" 2>/dev/null)
chk "honor_labels=true 时 job" "$HJ" "l8-app"
HN=$(curl -s -G 'http://localhost:19116/api/v1/query' --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(','.join(sorted({s['metric'].get('job','') for s in d['data']['result']})))" 2>/dev/null)
echo "  honor_labels=false 时 job = $HN"
echo "$HN" | grep -q 'federate-leaf' && ok "S3 false 时 job 被改写" || no "S3 job 未被改写"

echo "=== S4: HA 副本各自独立 ==="
R1=$(n 19112 'count(l8_card_balance)')
R2=$(n 19113 'count(l8_card_balance)')
chk "replica-1 本地条数" "$R1" "500"
chk "replica-2 本地条数" "$R2" "500"

echo "=== S5.1: 后端按 replica 分组 ==="
V1=$(n 19115 'count(l8_card_balance{replica="1"})')
V2=$(n 19115 'count(l8_card_balance{replica="2"})')
chk "后端 replica=1 条数" "$V1" "500"
chk "后端 replica=2 条数" "$V2" "500"

echo "=== S5.2: VM flags 端点 ==="
FL=$(curl -s "http://localhost:19115/flags" | tr ' ' '\n' | grep -c 'dedup.minScrapeInterval')
[ "$FL" -ge 1 ] && ok "S5.2 /flags 返回 dedup 参数" || no "S5.2 /flags"

echo "=== S5.3: 查询时聚合掉 replica ==="
RAW=$(curl -s -G 'http://localhost:19115/api/v1/query' --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['data']['result']))")
AGG=$(curl -s -G 'http://localhost:19115/api/v1/query' --data-urlencode 'query=max without(replica) (l8_card_balance{idx="0001"})' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d['data']['result']))")
chk "不聚合条数" "$RAW" "2"
chk "max without(replica) 条数" "$AGG" "1"

echo "=== S6: 无 replica 对照 ==="
NR=$(n 19117 'count(l8_card_balance)')
chk "无 replica 后端条数（dedup 合并）" "$NR" "500"

echo "=== S6.2: external_labels 附加位置 ==="
LOC=$(curl -s -G 'http://localhost:19110/api/v1/query' --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python3 -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print('cluster' in r[0]['metric'] if r else 'ERR')")
chk "本地查询含 cluster 标签" "$LOC" "False"
FED=$(curl -s -G 'http://localhost:19110/federate' --data-urlencode 'match[]={__name__="l8_card_balance",idx="0001"}' | grep -c 'cluster="leaf-a"')
chk "federate 出站含 cluster" "$FED" "1"

echo "=== S7: Alertmanager gossip ==="
P1=$(curl -s "http://localhost:19120/api/v2/status" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('cluster',{}).get('peers',[])))" 2>/dev/null)
P2=$(curl -s "http://localhost:19121/api/v2/status" | python3 -c "import sys,json;d=json.load(sys.stdin);print(len(d.get('cluster',{}).get('peers',[])))" 2>/dev/null)
chk "am-1 peers 数" "${P1:-0}" "1"
chk "am-2 peers 数" "${P2:-0}" "1"
echo "  （注：exp6 最后跑的是孤立场景，peers=1 是当前实际状态）"

echo
echo "=== 汇总: PASS=$PASS FAIL=$FAIL ==="
