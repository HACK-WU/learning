#!/usr/bin/env bash
# 知识点 3 决定性：external_labels 加在哪、用错的后果
set -u
echo "############ E1: external_labels 到底加在哪？ ############"
echo "   叶子 leaf-a 的 external_labels: cluster=leaf-a, region=cn-south"
echo
echo "  --- 本地查询（叶子自己的视角）：能看到 cluster 吗？ ---"
curl -s -G "http://localhost:19110/api/v1/query" \
  --data-urlencode 'query=l8_card_balance{idx="0001"}' \
  | python -c "
import sys,json
d=json.load(sys.stdin)
r=d['data']['result']
print('   ',sorted(r[0]['metric'].items()) if r else 'NONE')
print('   --> 本地查询结果里**没有** cluster/region')
print('       external_labels 不影响本地查询，只影响出站数据')
"

echo
echo "  --- 出站（federate 端点）：能看到 cluster 吗？ ---"
curl -s -G "http://localhost:19110/federate" \
  --data-urlencode 'match[]={__name__="l8_card_balance",idx="0001"}' \
  | grep -v '^#'
echo "   --> 出站数据**带上了** cluster/region"

echo
echo "############ E2: 用错的后果 —— 全局查询出现重复 ############"
echo "   对照组（norep-1 / norep-2）：两个副本 external_labels 完全相同"
echo
echo "  --- 两个副本本地各有多少条 ---"
for p in 19118 19119; do
  n=$(curl -s -G "http://localhost:$p/api/v1/query" --data-urlencode 'query=count(l8_card_balance)' \
    | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
  echo "   端口 $p 本地 = $n 条"
done
echo
echo "  --- 后端（19117）收到 ---"
n=$(curl -s -G "http://localhost:19117/api/v1/query" --data-urlencode 'query=count(l8_card_balance)' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
echo "   后端 = $n 条  <- dedup 合并掉了（因为标签完全相同）"
echo
echo "  --- 对照：带 replica 的后端（19115）---"
n2=$(curl -s -G "http://localhost:19115/api/v1/query" --data-urlencode 'query=count(l8_card_balance)' \
  | python -c "import sys,json;d=json.load(sys.stdin);r=d['data']['result'];print(r[0]['value'][1] if r else 'N/A')")
echo "   后端 = $n2 条  <- 保留两份，靠 replica 区分（正确做法）"

echo
echo "############ E3: external_labels 与告警的关系 ############"
echo "   告警规则在**本地**求值，本地查询看不到 external_labels"
echo "   -> external_labels **不会**进入告警标签（除非告警规则里显式写死）"
echo "   -> 但告警发给 Alertmanager 时，Prometheus 会把 external_labels 附加上去"
echo
echo "   验证：查 replica-1 的 external labels"
curl -s -G "http://localhost:19112/api/v1/status/config" \
  | python -c "
import sys,json,yaml
d=json.load(sys.stdin)
c=yaml.safe_load(d['data']['yaml'])
print('   external_labels =', c.get('global',{}).get('external_labels'))
"
