#!/usr/bin/env bash
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-12
NET=l12net

# 两个完全相同的实例：A 删除，B 不删除。对比同期磁盘增长。
mk_instance() {   # $1=name $2=port $3=datadir
  docker rm -f $1 2>/dev/null || true
  rm -rf $3; mkdir -p $3
  docker run -d --name $1 --network $NET \
    -v $D/cfg:/cfg:ro -v $3:/prometheus -p $2:9090 \
    prom/prometheus:v3.14.0 \
    --config.file=/cfg/prometheus-l12.yml \
    --storage.tsdb.path=/prometheus \
    --storage.tsdb.retention.time=1h \
    --web.enable-admin-api --web.enable-lifecycle >/dev/null
}
disk() { docker exec $1 sh -c "du -sk /prometheus 2>/dev/null | cut -f1"; }

echo "===== 起两个实例（app 已停，只有 self-scrape） ====="
docker stop l12-app >/dev/null 2>&1 || true
mk_instance l12-A 19510 $D/dataA
mk_instance l12-B 19511 $D/dataB
for p in 19510 19511; do
  for i in $(seq 1 40); do
    curl -sf http://localhost:$p/-/ready >/dev/null 2>&1 && break
    sleep 1
  done
done
sleep 25

echo
echo "===== 基线 ====="
echo "A disk = $(disk l12-A) KB"
echo "B disk = $(disk l12-B) KB"

echo
echo "===== 对 A 执行 delete_series，B 不动 ====="
curl -s -XPOST "http://localhost:19510/api/v1/admin/tsdb/delete_series" \
  --data-urlencode 'match[]=l12_series' -w "A delete HTTP=%{http_code}\n"
sleep 5

echo "A disk（删后） = $(disk l12-A) KB"
echo "B disk（同期） = $(disk l12-B) KB"

echo
echo "===== 结论 ====="
python3 - <<'PY'
import subprocess
def dk(c): return int(subprocess.run(["docker","exec",c,"sh","-c","du -sk /prometheus | cut -f1"],
    capture_output=True,text=True).stdout.strip())
a,b = dk("l12-A"), dk("l12-B")
print(f"A(删除) = {a} KB    B(不删) = {b} KB")
print(f"差值 = {a-b} KB   → 这就是 tombstone 的净增（已扣除 self-scrape 自然增长）")
PY
