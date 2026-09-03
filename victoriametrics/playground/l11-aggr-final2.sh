#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. keep_metric_names=true 时 outputs 只能有 1 个 → 改为单 output ==="
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__="up"}'
  interval: 30s
  outputs: [sum_samples]
  keep_metric_names: true
EOF
cat $P/stream-aggr.yml | sed 's/^/    /'

docker rm -f vmagent-aggr >/dev/null 2>&1
rm -rf $P/vmagent-aggr-data4 && mkdir -p $P/vmagent-aggr-data4
docker run -d --name vmagent-aggr --network $NET \
  -p 8437:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/stream-aggr.yml:/etc/stream-aggr.yml:ro \
  -v $P/vmagent-aggr-data4:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/79/prometheus \
  -remoteWrite.streamAggr.config=/etc/stream-aggr.yml \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 55

echo "  启动 fatal: $(docker logs vmagent-aggr 2>&1 | grep -c fatal)"
echo "  容器: $(docker ps --filter name=vmagent-aggr --format '{{.Status}}')"

echo
echo "  --- tenant 79 指标清单 ---"
curl -s "http://localhost:8487/select/79/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); names=d['data']
print('     指标数 =', len(names))
for n in names: print('       ', n)
" 2>/dev/null

echo
echo "  --- 聚合产物 up:sum_samples ---"
curl -s "http://localhost:8487/select/79/prometheus/api/v1/query?query=up:sum_samples" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
if not rs: print('     无数据')
for r in rs: print('     %-44s = %s' % (str(r['metric'])[:42], r['value'][1]))
" 2>/dev/null

echo
echo "  --- 原始 up 是否保留（keep_input 默认 true）---"
curl -s "http://localhost:8487/select/79/prometheus/api/v1/query?query=up" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
if not rs: print('     无数据')
for r in rs: print('     job=%-14s instance=%-22s = %s' % (r['metric'].get('job'), r['metric'].get('instance'), r['value'][1]))
" 2>/dev/null

echo
echo "=== 2. 基数缩减对照 ==="
t79=$(curl -s "http://localhost:8487/select/79/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
t0=$(curl -s "http://localhost:8487/select/0/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
echo "     tenant 79（含流式聚合）指标数 = $t79"
echo "     tenant 0 （原始全量）  指标数 = $t0"

echo
echo "=== 3. 清理 ==="
docker rm -f vmagent-aggr >/dev/null 2>&1
echo "  已清理"
