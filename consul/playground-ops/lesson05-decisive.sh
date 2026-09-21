#!/usr/bin/env bash
# 决定性实验：快照到底含不含 CA 私钥
# 判据：全毁集群 → 用快照恢复 → CA root ID 是否还原 + 能否签发叶子证书
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops
mkdir -p $D/tls

echo "########## 阶段1：记录恢复前的 CA 指纹 ##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots > $D/tls/roots_before.json
python3 - <<'PYEOF'
import json
d=json.load(open('/tmp/consul-ops/tls/roots_before.json'))
print(f"  ActiveRootID(前) = {d.get('ActiveRootID')}")
for r in d.get('Roots',[]):
    print(f"    Root ID={r.get('ID')} Name={r.get('Name')} Serial={r.get('SerialNumber')}")
    print(f"    RootCert 前40 = {r.get('RootCert','')[:40]}")
PYEOF

echo
echo "########## 阶段2：打数据标记（验证快照恢复的数据面）##########"
curl -s -X PUT -d 'before-snap' $CONSUL_HTTP_ADDR/v1/kv/lesson5/marker > /dev/null
echo "  写入 lesson5/marker = before-snap"

echo
echo "########## 阶段3：保存快照 ##########"
consul snapshot save $D/tls/full.snap 2>&1 | sed 's/^/  /'
echo "  快照大小 = $(stat -c%s $D/tls/full.snap) 字节"

echo
echo "########## 阶段4：全毁（停节点 + 清空 data_dir）##########"
pkill -f 'consul agent' 2>/dev/null
sleep 3
echo "  剩余 consul 进程 = $(pgrep -fc 'consul agent' 2>/dev/null || echo 0)"
rm -rf $D/data/node1 $D/data/node2 $D/data/node3
echo "  已删除 data/node1,2,3"

echo
echo "########## 阶段5：全新集群启动（会生成全新的 CA）##########"
bash $D/gen-conf.sh > /dev/null 2>&1
nohup consul agent -config-file=$D/conf/node1.hcl > $D/logs/node1.log 2>&1 &
sleep 2
nohup consul agent -config-file=$D/conf/node2.hcl > $D/logs/node2.log 2>&1 &
nohup consul agent -config-file=$D/conf/node3.hcl > $D/logs/node3.log 2>&1 &
sleep 15
consul operator raft list-peers 2>&1 | sed 's/^/  /'

echo
echo "########## 阶段6：新集群的 CA（应该和旧的不同）##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots > $D/tls/roots_new.json
python3 - <<'PYEOF'
import json
try:
    d=json.load(open('/tmp/consul-ops/tls/roots_new.json'))
    print(f"  ActiveRootID(新集群) = {d.get('ActiveRootID')}")
    for r in d.get('Roots',[]):
        print(f"    Root ID={r.get('ID')}")
except Exception as e:
    print(f"  读取失败: {e}")
    print(open('/tmp/consul-ops/tls/roots_new.json').read()[:300])
PYEOF
