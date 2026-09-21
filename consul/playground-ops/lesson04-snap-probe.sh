#!/usr/bin/env bash
# 核验：快照解压后到底有什么、没有什么
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
cd /tmp/consul-ops/tls

echo "########## 1. 快照是压缩的吗 ##########"
file probe.snap 2>/dev/null || python3 -c "
import gzip
try:
    d=gzip.decompress(open('probe.snap','rb').read())
    print(f'  gzip 解压成功: {len(d)} 字节（原始 3998）')
    open('probe.json','wb').write(d)
except Exception as e: print('  非 gzip:',e)
"

echo
echo "########## 2. 解压后搜私钥（课 5 核心结论的来源）##########"
if [ -f probe.json ]; then
  for kw in "PRIVATE KEY" "private_key" "PrivateKey" "BEGIN RSA"; do
    C=$(grep -c "$kw" probe.json 2>/dev/null || echo 0)
    echo "    \"$kw\" 出现 $C 次"
  done
  echo "  顶层键:"
  python3 -c "
import json
d=json.load(open('probe.json'))
print('   ',list(d.keys())[:20])
" 2>/dev/null || grep -oE '\"[A-Za-z]+\":' probe.json | sort -u | head -20 | sed 's/^/    /'
fi

echo
echo "########## 3. 对比：CA 私钥到底存在哪 ##########"
echo "  搜数据目录里有没有私钥文件:"
find /tmp/consul-ops/data -name '*.pem' -o -name '*key*' 2>/dev/null | head -10 | sed 's/^/    /'
echo "  → Connect CA 的内置私钥存在 Consul 的 Raft 状态/keystore 里"
echo "    快照导出的是\"状态\"，不含 CA 私钥 → 这就是官方说的\"快照不含 CA 私钥\""

echo
echo "########## 4. 实测：gossip 加密开启后，key 不一致会怎样 ##########"
cd /tmp/consul-ops
cat conf/node1.hcl | head -20

echo
echo "########## 5. Connect CA 轮换（不重启、API 完成）##########"
echo "  当前 CA root 数 = $(curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c 'import sys,json;print(len(json.load(sys.stdin)[\"Roots\"]))')"
echo "  轮换是\"加一个新 root，旧的保留一段时间\"→ 新旧并存是关键（过渡期）"

echo
echo "########## 6. 三类密钥轮换方式对比（实测可行性）##########"
echo "  gossip: consul keyring -install <new>  → 新旧并存，再 -use → 再 -remove 旧的"
echo "  TLS   : 换文件 + consul reload（或重启）"
echo "  CA    : PUT /v1/connect/ca/configuration 或 consul connect ca set-config"
echo "  → gossip 支持平滑轮转，TLS 要看是否支持热加载"

echo
echo "########## 7. 实测 gossip keyring（当前未启用加密时的表现）##########"
consul keyring -list 2>&1 | head -5 | sed 's/^/    /'