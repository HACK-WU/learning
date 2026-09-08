#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net
disk() { docker exec $1 sh -c "du -sk /prometheus 2>/dev/null | cut -f1"; }
q() { curl -s "http://localhost:$1/api/v1/query?query=$2" | python3 -c "
import json,sys
r=json.load(sys.stdin)['data']['result']
print(r[0]['value'][1] if r else 'empty')"; }

echo "===== 确保 app 在跑且有数据 ====="
docker start l12-app >/dev/null 2>&1 || true
sleep 20
echo "A: count(l12_series) = $(q 19510 'count(l12_series)')"
echo "B: count(l12_series) = $(q 19511 'count(l12_series)')"

echo
echo "===== 停 app，让数据静止（避免新样本干扰） ====="
docker stop l12-app >/dev/null
sleep 10
echo "A disk 基线 = $(disk l12-A) KB"
echo "B disk 基线 = $(disk l12-B) KB"
echo "A count = $(q 19510 'count(l12_series)')"
echo "B count = $(q 19511 'count(l12_series)')"

echo
echo "===== A 删除，B 不动 ====="
curl -s -XPOST "http://localhost:19510/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]=l12_series' -w "HTTP=%{http_code}\n"
sleep 6

echo "A disk（删后）= $(disk l12-A) KB   count=$(q 19510 'count(l12_series)')"
echo "B disk（同期）= $(disk l12-B) KB   count=$(q 19511 'count(l12_series)')"

echo
python3 - <<'PY'
import subprocess
def dk(c): return int(subprocess.run(["docker","exec",c,"sh","-c","du -sk /prometheus | cut -f1"],
    capture_output=True,text=True).stdout.strip())
a,b = dk("l12-A"), dk("l12-B")
print(f"tombstone 净增 = {a-b} KB（A删除 {a} - B未删 {b}）")
PY

echo
echo "===== A 执行 clean_tombstones，看 head 数据是否释放 ====="
curl -s -XPOST "http://localhost:19510/api/v1/admin/tsdb/clean_tombstones" -w "HTTP=%{http_code}\n"
sleep 5
echo "A disk（clean 后）= $(disk l12-A) KB"
echo "B disk（同期）    = $(disk l12-B) KB"
