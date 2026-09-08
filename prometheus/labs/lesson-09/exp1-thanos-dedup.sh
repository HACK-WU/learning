#!/usr/bin/env bash
# Thanos HA 去重决定性对照（回收课 8 挂账项：replica 思想在 Thanos 中的演进）
# 对照：开启 --query.replica-label=replica vs 关闭（再加一个不设 replica-label 的 querier）
set -uo pipefail
NET=l9net
Q=http://l9-thanos-query:19191

q() {  # $1=PromQL
  docker run --rm --network $NET curlimages/curl:latest -s -G \
    --data-urlencode "query=$1" "$Q/api/v1/query" 2>/dev/null
}

cnt() { # 统计返回序列条数
  python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(len(d.get('data',{}).get('result',[])))
except Exception as e:
    print('ERR')
"
}

echo "############ 实验 A：两个副本的原始序列（不去重）############"
echo "-- A1. 直接查 app_requests_total，看有几条 --"
q 'app_requests_total{route="/"}' | cnt | sed 's/^/   序列条数: /'

echo "-- A2. 按 replica 分组看各自的值 --"
q 'app_requests_total{route="/"}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',{}).get('result',[]):
    m=r['metric']
    print('   replica=%-4s cluster=%-14s value=%s' % (
        m.get('replica'), m.get('cluster'), r['value'][1]))
"

echo
echo "############ 实验 B：querier 已设 --query.replica-label=replica ############"
echo "-- B1. 查询时应自动去重为 1 条 --"
q 'sum by (route) (app_requests_total)' | cnt | sed 's/^/   结果条数: /'

echo "-- B2. 用 count() 验证去重是否真的发生 --"
q 'count(app_requests_total{route="/"})' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',{}).get('result',[]):
    print('   count = %s  (2=未去重, 1=已去重)' % r['value'][1])
"

echo
echo "############ 实验 C：显式不含 replica 的聚合（对比）############"
q 'count by (route) (app_requests_total)' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',{}).get('result',[]):
    print('   route=%-12s count=%s' % (r['metric'].get('route'), r['value'][1]))
"

echo
echo "############ 实验 D：不去掉 replica 标签时（保留原始）############"
q 'count by (replica) (app_requests_total)' | python3 -c "
import sys,json
d=json.load(sys.stdin)
for r in d.get('data',{}).get('result',[]):
    print('   replica=%-4s count=%s' % (r['metric'].get('replica'), r['value'][1]))
"

echo
echo "############ 实验 E：penalty 去重算法下的取值（谁胜出）############"
q 'app_requests_total{route="/"}' | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('   去重后剩余序列（应只剩 1 条，penalty 算法选其一）:')
for r in d.get('data',{}).get('result',[]):
    m=r['metric']
    print('     %s = %s' % (m, r['value'][1]))
"
