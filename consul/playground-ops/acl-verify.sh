#!/usr/bin/env bash
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
SECRET=$(grep 'SecretID' "$BASE/acl/boot.txt" | awk '{print $2}')

echo "===== 无 token 访问（default_policy=deny）====="
echo "-- 读 KV --"
curl -s "http://127.0.0.1:8501/v1/kv/ops/?keys" -w "\nHTTP=%{http_code}\n" | tail -3
echo "-- 列节点 --"
curl -s "http://127.0.0.1:8501/v1/catalog/nodes" -w "\nHTTP=%{http_code}\n" | tail -3

echo
echo "===== 带 token 访问 ====="
echo "-- 读 KV --"
curl -s -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/kv/ops/?keys" -w "\nHTTP=%{http_code}\n"
echo "-- 列节点 --"
curl -s -H "X-Consul-Token: $SECRET" "http://127.0.0.1:8501/v1/catalog/nodes" | python3 -c "import sys,json;print([n['Node'] for n in json.load(sys.stdin)])"

echo
echo "===== 创建一个只读 policy + token（最小权限）====="
cat > "$BASE/acl/kv-read.json" <<'EOF'
{
  "Name": "ops-kv-read",
  "Rules": "key_prefix \"ops/\" { policy = \"read\" }"
}
EOF
consul acl policy create -name ops-kv-read -rules @<(echo 'key_prefix "ops/" { policy = "read" }') -token "$SECRET" 2>&1 | head -5

echo
echo "-- 用只读 token 读/写 --"
TOK=$(consul acl token create -description "read-only" -policy-name ops-kv-read -token "$SECRET" -format=json 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['SecretID'])")
echo "new token: ${TOK:0:12}..."
curl -s -H "X-Consul-Token: $TOK" "http://127.0.0.1:8501/v1/kv/ops/?keys" -w " (read HTTP=%{http_code})\n"
curl -s -X PUT -d 'nope' -H "X-Consul-Token: $TOK" "http://127.0.0.1:8501/v1/kv/ops/hack" -w " (write HTTP=%{http_code})\n"
curl -s -H "X-Consul-Token: $TOK" "http://127.0.0.1:8501/v1/catalog/nodes" -w " (catalog HTTP=%{http_code})\n"
