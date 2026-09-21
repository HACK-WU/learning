#!/usr/bin/env bash
# 知识点 1：指标暴露方式——Prometheus 端点实测
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501

echo "########## 1. Prometheus 端点是否可用（telemetry 已开）##########"
curl -s -o /dev/null -w "  /v1/agent/metrics?format=prometheus → HTTP=%{http_code}\n" http://127.0.0.1:8501/v1/agent/metrics?format=prometheus
curl -s -o /dev/null -w "  /v1/agent/metrics (JSON)      → HTTP=%{http_code}\n" http://127.0.0.1:8501/v1/agent/metrics

echo
echo "########## 2. 指标总量与命名前缀 ##########"
curl -s "http://127.0.0.1:8501/v1/agent/metrics?format=prometheus" > /tmp/consul-ops/p.txt
echo "  总行数 = $(wc -l < /tmp/consul-ops/p.txt)"
echo "  非注释指标行数 = $(grep -c '^consul' /tmp/consul-ops/p.txt)"
echo "  前缀分布:"
grep '^consul' /tmp/consul-ops/p.txt | sed 's/^\(consul_[a-zA-Z0-9_]*\).*/\1/' | awk -F_ '{print $2}' | sort | uniq -c | sort -rn | head -12 | sed 's/^/    /'

echo
echo "########## 3. agent 层 vs server 层：两台机器指标一样吗 ##########"
for n in 1 2 3; do
  CNT=$(curl -s "http://127.0.0.$n:$((8500+n))/v1/agent/metrics?format=prometheus" | grep -c '^consul')
  echo "  node$n: $CNT 条指标"
done

echo
echo "########## 4. 关掉 telemetry 会怎样（默认是否开）##########"
grep -A2 'telemetry' /tmp/consul-ops/conf/node1.hcl

echo
echo "########## 5. Prometheus 格式 vs JSON：同一指标对照 ##########"
echo "  -- Prometheus --"
grep -E '^consul_raft_(last|applied)_index ' /tmp/consul-ops/p.txt | head -4 | sed 's/^/    /'
echo "  -- JSON --"
curl -s http://127.0.0.1:8501/v1/agent/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin); g=d.get('Gauges',{})
if isinstance(g,list): g={s['Name']:s for s in g if isinstance(s,dict) and 'Name' in s}
for k,v in g.items():
    if 'raft.last_index' in k or 'raft.applied_index' in k:
        print(f'    {k} = {v[\"Value\"] if isinstance(v,dict) else v}')
"