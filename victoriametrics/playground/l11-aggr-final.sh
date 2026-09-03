#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. 用官方推荐语法重做：match 用 {__name__=...} ==="
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__="up"}'
  interval: 30s
  outputs: [sum_samples, count_samples]
  keep_metric_names: true
EOF
echo "  配置（去掉 drop_input，避免丢原始数据）："
cat $P/stream-aggr.yml | sed 's/^/    /'

docker rm -f vmagent-aggr >/dev/null 2>&1
rm -rf $P/vmagent-aggr-data3 && mkdir -p $P/vmagent-aggr-data3
docker run -d --name vmagent-aggr --network $NET \
  -p 8437:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/stream-aggr.yml:/etc/stream-aggr.yml:ro \
  -v $P/vmagent-aggr-data3:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/78/prometheus \
  -remoteWrite.streamAggr.config=/etc/stream-aggr.yml \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 55

echo
echo "  --- tenant 78 指标清单 ---"
curl -s "http://localhost:8487/select/78/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); names=d['data']
print('     指标数 =', len(names))
for n in names: print('       ', n)
" 2>/dev/null

echo
echo "  --- 聚合产物 ---"
for m in "up:sum_samples" "up:count_samples" "up"; do
curl -s "http://localhost:8487/select/78/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
if not rs: print('     %-20s 无数据' % '$m')
for r in rs: print('     %-20s %-44s = %s' % ('$m', str(r['metric'])[:42], r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 2. 若仍无产物：检查 streamAggr 是否需要 -remoteWrite.streamAggr.dedupInterval ==="
echo "  --- vmagent 日志中的 streamaggr 相关信息 ---"
docker logs vmagent-aggr 2>&1 | grep -iE "stream|aggr" | tail -8 | sed 's/^/    /'

echo
echo "=== 3. 基数缩减对照：聚合前后 ==="
t78=$(curl -s "http://localhost:8487/select/78/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
t0=$(curl -s "http://localhost:8487/select/0/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
echo "     tenant 78（vmagent 采集，含聚合）指标数 = $t78"
echo "     tenant 0 （vmagent 采集，原始）  指标数 = $t0"

echo
echo "=== 4. 清理 ==="
docker rm -f vmagent-aggr >/dev/null 2>&1
echo "  已清理"
