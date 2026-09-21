#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
echo "########## 1. 版本与协议 ##########"
consul version 2>&1 | sed 's/^/  /'

echo
echo "########## 2. agent 自报的版本/协议（HTTP API）##########"
curl -s $CONSUL_HTTP_ADDR/v1/agent/self > $D/tls/self.json 2>&1
python3 -c "
import json
d=json.load(open('$D/tls/self.json'))
c=d.get('Config',{}); s=d.get('Stats',{}).get('consul',{})
print(f'  Version          = {c.get(\"Version\")}')
print(f'  VersionPrerelease= {c.get(\"VersionPrerelease\")}')
print(f'  Protocol(配置)   = {c.get(\"Protocol\")}')
print(f'  Datacenter       = {c.get(\"Datacenter\")}')
print(f'  Server           = {c.get(\"Server\")}')
print(f'  Bootstrap        = {c.get(\"Bootstrap\")}')
print(f'  --- Stats.consul ---')
for k in ['leader','server','term','last_log_index','last_log_term','known_servers']:
    print(f'  {k:16s} = {s.get(k)}')
"

echo
echo "########## 3. 集群成员的 protocol 版本（升级时的关键判据）##########"
curl -s $CONSUL_HTTP_ADDR/v1/agent/members 2>&1 | python3 -c "
import sys,json
for m in json.load(sys.stdin):
    print(f\"  {m['Name']:12s} Addr={m['Addr']:12s} Protocol={m.get('ProtocolCur')}→{m.get('ProtocolMax')} Status={m['Status']} Type={'server' if m.get('Tags',{}).get('role')=='consul' else 'client'}\")
"

echo
echo "########## 4. Raft 状态（升级时的操作顺序依据）##########"
curl -s $CONSUL_HTTP_ADDR/v1/status/leader 2>&1 | sed 's/^/  leader: /'
consul operator raft list-peers 2>&1 | sed 's/^/  /'

echo
echo "########## 5. 当前已有多少数据（回滚代价的基数）##########"
curl -s "$CONSUL_HTTP_ADDR/v1/kv/?keys=true" 2>&1 | sed 's/^/  /'
