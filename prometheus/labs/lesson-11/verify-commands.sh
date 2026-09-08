#!/usr/bin/env bash
# 逐字执行讲义第四幕命令（关键几条）
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (expect=$3 actual=$2)"; FAIL=$((FAIL+1)); fi; }

echo "===== 实验 0：环境准备（app 能否产出序列）====="
docker rm -f l11c-vapp >/dev/null 2>&1 || true
docker network create l11cnet >/dev/null 2>&1 || true
docker run -d --name l11c-vapp --network l11cnet -e N_SERIES=50000 -e VAL_LEN=12 -e LABELS=1 l11c-app >/dev/null
sleep 3
N=$(docker exec l11c-vapp python3 -c "
import urllib.request
n=0
for _ in urllib.request.urlopen('http://localhost:8000/metrics',timeout=60): n+=1
print(n)")
echo "  /metrics 行数 = $N"
ck "app 产出 50002 行" "$N" "50002"

echo ""
echo "===== 实验 4：self-scrape 前后指标数 ====="
docker rm -f l11c-vprom >/dev/null 2>&1 || true
docker run -d --name l11c-vprom --network l11cnet -p 19459:9090 \
  -v $D/prometheus-self.yml:/etc/prometheus/prometheus.yml:ro \
  prom/prometheus:v3.14.0 --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus --web.enable-lifecycle --web.enable-admin-api >/dev/null
for i in $(seq 1 60); do curl -sf "http://localhost:19459/-/ready" >/dev/null 2>&1 && break; sleep 1; done
sleep 45
CNT=$(curl -s "http://localhost:19459/api/v1/label/__name__/values" | python3 -c "
import sys,json;print(len(json.load(sys.stdin)['data']))")
echo "  指标总数 = $CNT (讲义称 328 量级，含业务指标)"
ck "指标数 > 300（self-scrape 生效）" "$([ $CNT -gt 300 ] && echo yes || echo no)" "yes"

HS=$(curl -s --data-urlencode 'query=prometheus_tsdb_head_series' "http://localhost:19459/api/v1/query" \
  | python3 -c "
import sys,json;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'NONE')")
echo "  prometheus_tsdb_head_series = $HS"
ck "head_series 有值（课10结论已纠正）" "$([ "$HS" != "NONE" ] && echo yes || echo no)" "yes"

PRM=$(curl -s --data-urlencode 'query=process_resident_memory_bytes/1024/1024' "http://localhost:19459/api/v1/query" \
  | python3 -c "
import sys,json;r=json.load(sys.stdin)['data']['result'];print(r[0]['value'][1] if r else 'NONE')")
echo "  process_resident_memory_bytes(MiB) = $PRM"

echo ""
echo "===== 实验 1：measure.sh 可跑通 ====="
R=$(bash $D/measure.sh 50000 12 19460 3 2>/dev/null)
echo "  measure.sh 输出 = $R"
NS=$(echo "$R" | cut -d'|' -f1)
ck "numSeries = 50005" "$NS" "50005"

echo ""
echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
echo ""
echo "清理..."
docker rm -f l11c-vprom l11c-vapp >/dev/null 2>&1
