#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net
q() { curl -s "http://localhost:$1/api/v1/query?query=$2" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"; }
disk() { docker exec $1 sh -c "du -sk /prometheus 2>/dev/null | cut -f1"; }

echo "#############################################################"
echo "# 关键验证：staleness 会污染'删除是否生效'的判断            #"
echo "# 方法：只删一部分序列（idx<\"00001000\"），未删的应仍可查   #"
echo "#############################################################"

echo
echo "===== 准备：app 在跑，数据新鲜 ====="
docker start l12-app >/dev/null 2>&1 || true
sleep 20

echo "--- 用 range 查询绕开 staleness（查最近 5 分钟有没有样本） ---"
cnt() { curl -s "http://localhost:$1/api/v1/query?query=$2" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"; }
echo "A: 总数 = $(cnt 19510 'count(l12_series)')"
echo "A: idx<00001000 的数量 = $(cnt 19510 'count(l12_series{idx<\"00001000\"})')"
echo "A: idx>=00001000 的数量 = $(cnt 19510 'count(l12_series{idx>=\"00001000\"})')"

echo
echo "===== 删除 idx<\"00001000\" 的部分序列 ====="
curl -s -XPOST -G "http://localhost:19510/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]=l12_series{idx<"00001000"}' -w "HTTP=%{http_code}\n"
sleep 5

echo
echo "===== 验证：删除是否精准生效（app 仍在跑，排除 staleness 干扰） ====="
echo "A: idx<00001000（已删）= $(cnt 19510 'count(l12_series{idx<\"00001000\"})')   <- 期望 0/empty"
echo "A: idx>=00001000（未删）= $(cnt 19510 'count(l12_series{idx>=\"00001000\"})')   <- 期望 19000"

echo
echo "===== 磁盘对比 ====="
echo "A disk（删了 1000 条）= $(disk l12-A) KB"
echo "B disk（未删）        = $(disk l12-B) KB"
