#!/bin/bash
P=/mnt/d/projects/learning/victoriametrics/playground
NET=vm-cluster-net

echo "=== 1. 重做流式聚合：只保留 up 的聚合，不改动其余指标 ==="
cat > $P/stream-aggr.yml <<'EOF'
- match: 'up'
  interval: 30s
  outputs: [sum_samples, count_samples]
  keep_metric_names: true
  keep_input: false
  drop_input: true
EOF
echo "  配置：match=up, outputs=[sum_samples,count_samples], keep_metric_names=true, drop_input=true"

docker rm -f vmagent-aggr >/dev/null 2>&1
mkdir -p $P/vmagent-aggr-data2
docker run -d --name vmagent-aggr --network $NET \
  -p 8437:8429 \
  -v $P/prometheus-vmagent.yml:/etc/prometheus/prometheus.yml:ro \
  -v $P/stream-aggr.yml:/etc/stream-aggr.yml:ro \
  -v $P/vmagent-aggr-data2:/vmagentdata \
  victoriametrics/vmagent:v1.151.0 \
  -promscrape.config=/etc/prometheus/prometheus.yml \
  -remoteWrite.url=http://vminsert-learn2:8480/insert/77/prometheus \
  -remoteWrite.streamAggr.config=/etc/stream-aggr.yml \
  -remoteWrite.tmpDataPath=/vmagentdata \
  -httpListenAddr=:8429 >/dev/null
sleep 55

echo
echo "  --- tenant 77 的指标清单 ---"
curl -s "http://localhost:8487/select/77/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
names=d['data']
print('     指标数 =', len(names))
for n in names: print('       ', n)
" 2>/dev/null

echo
echo "  --- 聚合产物值 ---"
for m in "up:sum_samples" "up:count_samples" "up"; do
curl -s "http://localhost:8487/select/77/prometheus/api/v1/query?query=$m" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin); rs=d['data']['result']
if not rs: print('     %-20s 无数据' % '$m')
for r in rs: print('     %-20s %-40s = %s' % ('$m', str(r['metric'])[:38], r['value'][1]))
" 2>/dev/null
done

echo
echo "=== 2. 基数缩减效果：tenant 77 vs tenant 0 ==="
t77=$(curl -s "http://localhost:8487/select/77/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
t0=$(curl -s "http://localhost:8487/select/0/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)['data']))" 2>/dev/null)
echo "     tenant 77（流式聚合后）指标数 = $t77"
echo "     tenant 0 （原始全量）  指标数 = $t0"

echo
echo "=== 3. 对照：keep_metric_names=false 的破坏性（复现第 5 步发现）==="
cat > $P/stream-aggr.yml <<'EOF'
- match: '{__name__=~".+"}'
  interval: 30s
  outputs: [sum_samples]
  keep_metric_names: false
EOF
docker restart vmagent-aggr >/dev/null 2>&1
sleep 45
echo "  --- 匹配所有指标 + 丢弃原名后，tenant 77 的指标 ---"
curl -s "http://localhost:8487/select/77/prometheus/api/v1/label/__name__/values" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
names=d['data']
print('     指标数 =', len(names))
for n in names[:10]: print('       ', n)
" 2>/dev/null
echo "  → 全量匹配 + keep_metric_names=false 会把所有指标名抹平成一个名字"

echo
echo "=== 4. 清理 ==="
docker rm -f vmagent-aggr >/dev/null 2>&1
echo "  已清理"
