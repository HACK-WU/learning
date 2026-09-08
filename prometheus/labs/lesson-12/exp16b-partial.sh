#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
cnt() { curl -s -G "http://localhost:$1/api/v1/query" --data-urlencode "query=$2" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"; }
disk() { docker exec $1 sh -c "du -sk /prometheus 2>/dev/null | cut -f1"; }

echo "#############################################################"
echo "# 关键验证：staleness 会污染'删除是否生效'的判断            #"
echo "# 方法：只删前缀为 00000 的序列（正则 =^00000），其余应仍可查#"
echo "#############################################################"

docker start l12-app >/dev/null 2>&1 || true
sleep 20

echo
echo "===== 删除前 ====="
echo "总数                 = $(cnt 19510 'count(l12_series)')"
echo "idx=~'00000.*'（待删）= $(cnt 19510 'count(l12_series{idx=~\"00000.*\"})')"
echo "idx=~'[1-9].*'（保留）= $(cnt 19510 'count(l12_series{idx=~\"[1-9].*\"})')"

echo
echo "===== 执行删除（正则匹配） ====="
curl -s -XPOST -G "http://localhost:19510/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]=l12_series{idx=~"00000.*"}' -w "HTTP=%{http_code}\n"
sleep 5

echo
echo "===== 删除后（app 仍在跑，排除 staleness 干扰） ====="
echo "idx=~'00000.*'（已删）= $(cnt 19510 'count(l12_series{idx=~\"00000.*\"})')   <- 期望 0/empty"
echo "idx=~'[1-9].*'（保留）= $(cnt 19510 'count(l12_series{idx=~\"[1-9].*\"})')   <- 期望非 0"

echo
echo "===== 磁盘：A（删）vs B（不删） ====="
echo "A disk = $(disk l12-A) KB"
echo "B disk = $(disk l12-B) KB"
