#!/usr/bin/env bash
# 实测：全新集群 bootstrap 出来的 CA 配置默认值到底是什么
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
D=/tmp/consul-ops

echo "########## 1. 全毁 ##########"
pkill -f 'consul agent' 2>/dev/null; sleep 3
rm -rf $D/data/node1 $D/data/node2 $D/data/node3
echo "  已清空"

echo
echo "########## 2. 起全新集群（不做任何 CA 配置写入）##########"
mkdir -p $D/logs
nohup consul agent -config-file=$D/conf/node1.hcl > $D/logs/node1.log 2>&1 &
sleep 2
nohup consul agent -config-file=$D/conf/node2.hcl > $D/logs/node2.log 2>&1 &
nohup consul agent -config-file=$D/conf/node3.hcl > $D/logs/node3.log 2>&1 &
sleep 18
echo "  进程数 = $(pgrep -fc 'consul agent')"

echo
echo "########## 3. 读取【未经任何写入】的 CA 配置默认值 ##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/configuration > $D/tls/default_cfg.json 2>&1
cat $D/tls/default_cfg.json | sed 's/^/  /'
echo

echo
echo "########## 4. 判定 ##########"
python3 -c "
import json
d=json.load(open('$D/tls/default_cfg.json'))
c=d.get('Config')
print(f'  Config = {c}')
print(f'  CreateIndex={d.get(\"CreateIndex\")} ModifyIndex={d.get(\"ModifyIndex\")}')
if c is None:
    print('  → 全新集群 Config 为 null：CA 配置无显式值')
    print('  → 说明 RotationPeriod/IntermediateCertTTL 未写入，按内置逻辑运行')
else:
    print(f'  → RotationPeriod = {c.get(\"RotationPeriod\")}')
    print(f'  → IntermediateCertTTL = {c.get(\"IntermediateCertTTL\")}')
"

echo
echo "########## 5. 全新集群的 CA root ##########"
curl -s $CONSUL_HTTP_ADDR/v1/connect/ca/roots | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(f'  ActiveRootID = {d.get(\"ActiveRootID\")}')
print(f'  Roots 数 = {len(d.get(\"Roots\",[]))}')
for r in d.get('Roots',[]):
    print(f'    NotAfter={r.get(\"NotAfter\")}')
"
