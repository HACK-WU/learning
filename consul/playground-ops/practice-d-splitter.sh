#!/bin/bash
# 实战篇 D 完整实测：灰度发布 / discovery chain / 网关控制面
# Consul 2.0.2，纯控制面（无 Envoy）
set -u
WORK=/tmp/practice-d
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1

consul agent -dev -client=127.0.0.1 -http-port=8580 -grpc-port=8530 \
  -dns-port=-1 -log-level=warn > agent.log 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null; wait $PID 2>/dev/null' EXIT
echo "等待 agent 就绪..."
for i in $(seq 1 40); do
  L=$(curl -s "http://127.0.0.1:8580/v1/status/leader" 2>/dev/null)
  [ -n "$L" ] && [ "$L" != '""' ] && { echo "leader: $L"; sleep 1; break; }
  sleep 1
done

echo ""
echo "########## 步骤 1：注册 v1/v2 两版服务 ##########"
for v in 1 2; do
  curl -s -X PUT "http://127.0.0.1:8580/v1/agent/service/register" -d "{
    \"Name\":\"web\",\"ID\":\"web-v${v}\",\"Port\":808${v},
    \"Meta\":{\"version\":\"${v}\"}
  }" >/dev/null
done
curl -s "http://127.0.0.1:8580/v1/catalog/service/web" | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('web 实例数:', len(d))
for x in d: print('  ', x['ServiceID'], 'port', x['ServicePort'], 'meta', x.get('ServiceMeta'))
"

echo ""
echo "########## 步骤 2：默认 chain（未声明协议）##########"
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
print('Protocol:', d.get('Protocol'), '| StartNode:', d.get('StartNode'), '| Default:', d.get('Default'))
"

echo ""
echo "########## 步骤 3：tcp 协议下写 splitter（预期失败）##########"
cat > s_tcp.hcl <<'EOF'
Kind = "service-splitter"
Name = "web"
Splits = [
  { Weight = 80, Service = "web" },
  { Weight = 20, Service = "web" },
]
EOF
consul config write -http-addr=127.0.0.1:8580 s_tcp.hcl 2>&1 | head -2

echo ""
echo "########## 步骤 4：声明 http 协议 ##########"
cat > defaults.hcl <<'EOF'
Kind = "service-defaults"
Name = "web"
Protocol = "http"
EOF
consul config write -http-addr=127.0.0.1:8580 defaults.hcl 2>&1 | head -2
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
print('Protocol:', d.get('Protocol'), '| StartNode:', d.get('StartNode'), '| Default:', d.get('Default'))
"

echo ""
echo "########## 步骤 5：权重和≠100（预期失败）##########"
cat > bad.hcl <<'EOF'
Kind = "service-splitter"
Name = "web"
Splits = [
  { Weight = 90, Service = "web" },
]
EOF
consul config write -http-addr=127.0.0.1:8580 bad.hcl 2>&1 | head -2

echo ""
echo "########## 步骤 6：ServiceResolver 定义子集 ##########"
cat > resolver.hcl <<'EOF'
Kind = "service-resolver"
Name = "web"
Subsets = {
  "v1" = { Filter = "Service.Meta.version == 1" }
  "v2" = { Filter = "Service.Meta.version == 2" }
}
EOF
consul config write -http-addr=127.0.0.1:8580 resolver.hcl 2>&1 | head -2

echo ""
echo "########## 步骤 7：灰度 90/10（权重和=100）##########"
cat > s1.hcl <<'EOF'
Kind = "service-splitter"
Name = "web"
Splits = [
  { Weight = 90, ServiceSubset = "v1" },
  { Weight = 10, ServiceSubset = "v2" },
]
EOF
consul config write -http-addr=127.0.0.1:8580 s1.hcl 2>&1 | head -2
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
print('StartNode:', d.get('StartNode'))
for k,v in (d.get('Nodes') or {}).items():
    if v.get('Type')=='splitter':
        for s in v['Splitter']['Splits']:
            print('   split ->', s.get('Weight'), '%', s.get('NextNode'))
for k,v in (d.get('Targets') or {}).items():
    print('   target', k, '| Subset filter:', (v.get('Subset') or {}).get('Filter'))
"

echo ""
echo "########## 步骤 8：调权重到 50/50（即时生效，无需重启）##########"
cat > s2.hcl <<'EOF'
Kind = "service-splitter"
Name = "web"
Splits = [
  { Weight = 50, ServiceSubset = "v1" },
  { Weight = 50, ServiceSubset = "v2" },
]
EOF
consul config write -http-addr=127.0.0.1:8580 s2.hcl 2>&1 | head -2
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
for k,v in (d.get('Nodes') or {}).items():
    if v.get('Type')=='splitter':
        for s in v['Splitter']['Splits']: print('   split ->', s.get('Weight'), '%', s.get('NextNode'))
"

echo ""
echo "########## 步骤 9：子集为空会怎样（负向：Filter 匹配不到）##########"
cat > resolver_bad.hcl <<'EOF'
Kind = "service-resolver"
Name = "web"
Subsets = {
  "v1" = { Filter = "Service.Meta.version == 1" }
  "v2" = { Filter = "Service.Meta.version == 2" }
  "v9" = { Filter = "Service.Meta.version == 9" }
}
EOF
consul config write -http-addr=127.0.0.1:8580 resolver_bad.hcl 2>&1|head -1
cat > s3.hcl <<'EOF'
Kind = "service-splitter"
Name = "web"
Splits = [
  { Weight = 50, ServiceSubset = "v1" },
  { Weight = 50, ServiceSubset = "v9" },
]
EOF
echo "--- 切 50% 到不存在的 v9 子集 ---"
consul config write -http-addr=127.0.0.1:8580 s3.hcl 2>&1 | head -2
echo "--- chain 是否接受 ---"
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
print('StartNode:', d.get('StartNode'))
print('Targets:', list((d.get('Targets') or {}).keys()))
" 2>&1

echo ""
echo "########## 步骤 10：ServiceRouter（按路径路由）##########"
cat > router.hcl <<'EOF'
Kind = "service-router"
Name = "web"
Routes = [
  {
    Match = { HTTP = { PathPrefix = "/api/v2" } }
    Destination = { Service = "web", ServiceSubset = "v2" }
  },
]
EOF
consul config write -http-addr=127.0.0.1:8580 router.hcl 2>&1 | head -2
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
print('StartNode:', d.get('StartNode'))
for k,v in (d.get('Nodes') or {}).items():
    print('  node', k, 'type=', v.get('Type'))
" 2>&1

echo ""
echo "########## 步骤 11：网关控制面（无 Envoy 能否写）##########"
cat > gw.hcl <<'EOF'
Kind = "ingress-gateway"
Name = "ingress-web"
Listeners = [
  { Port = 8080, Protocol = "http", Services = [ { Name = "web" } ] },
]
EOF
echo "--- IngressGateway ---"
consul config write -http-addr=127.0.0.1:8580 gw.hcl 2>&1 | head -2

cat > tgw.hcl <<'EOF'
Kind = "terminating-gateway"
Name = "term-external"
Services = [ { Name = "external-db" } ]
EOF
echo "--- TerminatingGateway ---"
consul config write -http-addr=127.0.0.1:8580 tgw.hcl 2>&1 | head -2

echo ""
echo "########## 步骤 12：网关是否真起进程（关键边界）##########"
echo "--- 本机监听端口（8080 应有吗）---"
ss -tln 2>/dev/null | grep -E ':8080|:8081|:8082' || echo "8080/8081/8082 均未监听 → 网关与后端都只是注册项，无真实进程"
echo "--- consul 进程数 ---"
ps aux | grep -c '[c]onsul agent'

echo ""
echo "########## 步骤 13：删除 splitter 后 chain 回到默认 ##########"
consul config delete -http-addr=127.0.0.1:8580 -kind service-splitter -name web 2>&1|head -1
consul config delete -http-addr=127.0.0.1:8580 -kind service-router -name web 2>&1|head -1
curl -s "http://127.0.0.1:8580/v1/discovery-chain/web" | python3 -c "
import sys,json
d=json.load(sys.stdin).get('Chain',{})
print('StartNode:', d.get('StartNode'), '| Default:', d.get('Default'))
" 2>&1

echo ""
echo "########## 步骤 14：consul config list 全量 ##########"
consul config list -http-addr=127.0.0.1:8580 -kind service-splitter 2>&1 | head -3
echo "--- resolver ---"
consul config list -http-addr=127.0.0.1:8580 -kind service-resolver 2>&1 | head -3
echo "--- ingress-gateway ---"
consul config list -http-addr=127.0.0.1:8580 -kind ingress-gateway 2>&1 | head -3
