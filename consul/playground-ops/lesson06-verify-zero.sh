#!/usr/bin/env bash
# 核验：Prometheus 端点报 0，JSON 报 29——哪个是真的？
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "########## 1. 写点数据，看两个端点会不会动 ##########"
for i in $(seq 1 50); do curl -s -o /dev/null -X PUT -d "v$i" $CONSUL_HTTP_ADDR/v1/kv/mon/$i; done
sleep 2

echo "  -- Prometheus --"
curl -s "http://127.0.0.1:8501/v1/agent/metrics?format=prometheus" | grep -E '^consul_raft_(last|applied)_index ' | sed 's/^/    /'
echo "  -- JSON --"
curl -s $CONSUL_HTTP_ADDR/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin); g=d.get('Gauges',{})
if isinstance(g,list): g={s['Name']:s for s in g if isinstance(s,dict) and 'Name' in s}
for k,v in g.items():
    if 'raft.last_index' in k or 'raft.applied_index' in k:
        print(f'    {k} = {v[\"Value\"] if isinstance(v,dict) else v}')
"
echo "  -- 权威来源：raft list-peers 的 Commit Index --"
consul operator raft list-peers | awk 'NR>1{print "    "$1" commit="$7}' | head -3

echo
echo "########## 2. Prometheus 端点里哪些指标非 0（找真指标）##########"
curl -s "http://127.0.0.1:8501/v1/agent/metrics?format=prometheus" | grep '^consul' | awk '{if($2!="0" && $2!="0.000000") print}' | head -25 | sed 's/^/    /'
echo "  （共 $(curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep '^consul' | awk '{if($2!="0" && $2!="0.000000") print}' | wc -l) 条非零）"

echo
echo "########## 3. 关键：leader 相关指标在 Prometheus 端点的值 ##########"
curl -s "http://127.0.0.1:8501/v1/agent/metrics?format=prometheus" | grep -iE 'leader|autopilot|healthy' | grep '^consul' | sed 's/^/    /'

echo
echo "########## 4. 全零指标占比（静默失效风险面）##########"
TOT=$(curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep -c '^consul')
ZERO=$(curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep '^consul' | awk '$2=="0"' | wc -l)
python3 -c "print(f'  共 {$TOT} 条，值为 0 的有 {$ZERO} 条 → {$ZERO/$TOT*100:.0f}%')"

echo
echo "########## 5. 有没有 HELP / TYPE 行（三步核验第 2 步的前提）##########"
echo "  HELP 行数 = $(grep -c '^# HELP' /tmp/consul-ops/p.txt 2>/dev/null || curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep -c '^# HELP')"
echo "  TYPE 行数 = $(curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep -c '^# TYPE')"
echo "  示例 HELP:"
curl -s 'http://127.0.0.1:8501/v1/agent/metrics?format=prometheus' | grep '^# HELP' | head -3 | sed 's/^/    /'
