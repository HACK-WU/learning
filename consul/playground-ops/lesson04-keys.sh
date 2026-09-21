#!/usr/bin/env bash
# 知识点 1：三类密钥是不是真的互相独立——拆开验证
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
mkdir -p /tmp/consul-ops/tls && cd /tmp/consul-ops/tls

echo "########## 1. 三类密钥在哪、长什么样 ##########"
echo "  -- gossip encryption key（配置项 encrypt）--"
grep -i 'encrypt' /tmp/consul-ops/conf/node1.hcl 2>/dev/null || echo "    当前集群未启用 gossip 加密（无 encrypt 项）"
echo "  -- 生成一个看看格式 --"
GK=$(consul keygen 2>/dev/null)
echo "    consul keygen → $GK"
echo "    长度 = ${#GK} 字符（base64 编码的 32 字节）"

echo
echo "########## 2. 三类密钥的存储位置对比 ##########"
echo "  gossip key  : 配置文件里（明文）→ 改配置 + 重启"
echo "  TLS 证书    : 磁盘文件（pem）→ 换文件 + reload（部分需重启）"
echo "  Connect CA  : Consul 内部（Raft 状态里）→ 通过 API 轮换"

echo
echo "########## 3. 实测：Connect CA 的当前状态 ##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c "
import sys,json,base64,datetime
d=json.load(sys.stdin)
print(f'    ActiveRootID = {d.get(\"ActiveRootID\")}')
print(f'    TrustDomain  = {d.get(\"TrustDomain\")}')
print(f'    Roots 数量   = {len(d.get(\"Roots\",[]))}')
for r in d.get('Roots',[]):
    pem=r['RootCert']
    print(f'      Root SerialNumber={r.get(\"SerialNumber\")}')
    print(f'      NotBefore={r.get(\"NotBefore\")} NotAfter={r.get(\"NotAfter\")}')
    print(f'      Active={r.get(\"Active\")}')
    nb=r.get('NotBefore'); na=r.get('NotAfter')
    if nb and na:
        try:
            f='%Y-%m-%dT%H:%M:%SZ'
            a=datetime.datetime.strptime(nb,f); b=datetime.datetime.strptime(na,f)
            print(f'      有效期跨度 = {(b-a).days} 天')
        except Exception as e: print('      解析:',e)
" 2>&1 | head -20

echo
echo "########## 4. 关键：CA 私钥在快照里吗（课 5 的核心伏笔）##########"
consul snapshot save /tmp/consul-ops/tls/probe.snap >/dev/null 2>&1
SZ=$(stat -c%s /tmp/consul-ops/tls/probe.snap)
echo "  快照大小 = $SZ 字节"
echo "  搜快照里有没有私钥关键字:"
for kw in "PRIVATE KEY" "EC PRIVATE" "BEGIN RSA" "consul"; do
  C=$(grep -c "$kw" /tmp/consul-ops/tls/probe.snap 2>/dev/null || echo 0)
  echo "    \"$kw\" 出现 $C 次"
done

echo
echo "########## 5. 三类密钥过期后各自的表现（能不能事后补救）##########"
echo "  gossip key 不一致 → 节点无法加入集群（gossip 层不通）"
echo "  TLS 证书过期     → 连接 TLS 握手失败"
echo "  Connect CA 过期  → 新证书签不出来，mTLS 建不起来"
echo "  → 三者都会导致\"节点看着在跑，实际不工作\""
