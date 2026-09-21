#!/usr/bin/env bash
D1=http://127.0.1.1:8500
D2=http://127.0.2.1:8500

echo "########## 1. 在 dc1 写数据 ##########"
curl -s -X PUT -d 'written-in-dc1' $D1/v1/kv/app/only-dc1 > /dev/null
echo "  dc1 读 app/only-dc1 = '$(curl -s $D1/v1/kv/app/only-dc1?raw)'"

echo
echo "########## 2. 从 dc2 跨 DC 读（关键实验）##########"
echo "  --- 本地读（不带 dc 参数）---"
echo "  dc2 读 app/only-dc1 = '$(curl -s $D2/v1/kv/app/only-dc1?raw 2>/dev/null)'"
echo "  --- 跨 DC 读（?dc=dc1）---"
echo "  dc2 读 ?dc=dc1      = '$(curl -s "$D2/v1/kv/app/only-dc1?dc=dc1&raw" 2>/dev/null)'"
echo "  --- 跨 DC HTTP 状态码 ---"
echo "  code = $(curl -s -o /dev/null -w '%{http_code}' "$D2/v1/kv/app/only-dc1?dc=dc1&raw")"

echo
echo "########## 3. 在 dc2 写，看 dc1 能否看到 ##########"
curl -s -X PUT -d 'written-in-dc2' $D2/v1/kv/app/only-dc2 > /dev/null
echo "  dc2 读 app/only-dc2 = '$(curl -s $D2/v1/kv/app/only-dc2?raw)'"
echo "  dc1 本地读           = '$(curl -s $D1/v1/kv/app/only-dc2?raw 2>/dev/null)'"
echo "  dc1 跨DC读 ?dc=dc2   = '$(curl -s "$D1/v1/kv/app/only-dc2?dc=dc2&raw" 2>/dev/null)'"

echo
echo "########## 4. 各自的 KV 键列表（证明是两份独立数据）##########"
echo "  dc1 keys: $(curl -s "$D1/v1/kv/?keys=true" | tr -d '[]"' | tr ',' ' ')"
echo "  dc2 keys: $(curl -s "$D2/v1/kv/?keys=true" | tr -d '[]"' | tr ',' ' ')"

echo
echo "########## 5. 服务跨 DC 查询（同样只是查询通道）##########"
curl -s -X PUT -H 'Content-Type: application/json' \
  -d '{"Name":"web","ID":"web-dc1","Address":"10.0.1.10","Port":8080}' \
  $D1/v1/agent/service/register > /dev/null
sleep 2
echo "  dc1 本地查 web     = $(curl -s $D1/v1/health/service/web | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d),"个实例")' 2>/dev/null)"
echo "  dc2 跨DC查 web     = $(curl -s "$D2/v1/health/service/web?dc=dc1" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d),"个实例 (来自dc1)")' 2>/dev/null)"
echo "  dc2 catalog 的 services:"
curl -s $D2/v1/catalog/services 2>/dev/null | sed 's/^/    /'

echo
echo "########## 6. 故障域验证：dc2 挂掉，dc1 是否受影响 ##########"
PID=$(pgrep -f 'conf/dc2-s1.hcl' | head -1)
kill -TERM $PID 2>/dev/null
sleep 8
echo "  dc2 已停"
echo "  dc1 写测试 = HTTP $(curl -s -o /dev/null -w '%{http_code}' -X PUT -d 'after-dc2-down' $D1/v1/kv/test/dc2down)"
echo "  dc1 读 app/only-dc1 = '$(curl -s $D1/v1/kv/app/only-dc1?raw)'"
echo "  dc1 members -wan:"; CONSUL_HTTP_ADDR=$D1 consul members -wan 2>&1 | sed 's/^/    /'
