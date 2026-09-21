#!/usr/bin/env bash
# 重测：用脚本专属临时文件，避免 /tmp/body.txt 被其他进程占用污染结论
BASE=/tmp/consul-ops
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
OUT=$(mktemp /tmp/consul-probe-XXXXXX.txt)

pkill -f 'consul agent' 2>/dev/null; sleep 2
rm -rf $BASE/data/node{1,2,3}; mkdir -p $BASE/data/node{1,2,3}
for i in 1 2 3; do
  nohup consul agent -config-file $BASE/conf/node$i.hcl > $BASE/log/node$i.log 2>&1 &
done
sleep 15
echo "基线（健康时）："
curl -s -o "$OUT" -w "  写 HTTP=%{http_code}\n" -X PUT -d ok $CONSUL_HTTP_ADDR/v1/kv/ops/probe
echo "  body=[$(head -c 40 "$OUT" | tr -d '\n')]"

pkill -f 'conf/node3.hcl'; sleep 8
pkill -f 'conf/node2.hcl'; sleep 8

echo
echo "坏 2 台后（无 quorum）："
for i in 1 2 3; do
  : > "$OUT"
  code=$(curl -s -o "$OUT" -w "%{http_code}" --max-time 8 -X PUT -d "x$i" $CONSUL_HTTP_ADDR/v1/kv/ops/probe)
  printf "  写%d HTTP=%s body=[%s]\n" "$i" "$code" "$(head -c 70 "$OUT" | tr -d '\n')"
done
for i in 1 2 3; do
  : > "$OUT"
  code=$(curl -s -o "$OUT" -w "%{http_code}" --max-time 8 $CONSUL_HTTP_ADDR/v1/kv/ops/probe?raw)
  printf "  读%d HTTP=%s body=[%s]\n" "$i" "$code" "$(head -c 70 "$OUT" | tr -d '\n')"
done

rm -f "$OUT"
pkill -f 'consul agent' 2>/dev/null; sleep 2
echo done
