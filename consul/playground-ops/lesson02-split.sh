#!/usr/bin/env bash
# 复验：修正 probe 端口 bug 后，重测多数派/少数派
BASE=/tmp/consul-ops

restore() {
  pkill -f 'consul agent' 2>/dev/null || true; sleep 2
  rm -rf "$BASE"/data/node{1,2,3}; mkdir -p "$BASE"/data/node{1,2,3}
  for i in 1 2 3; do nohup consul agent -config-file "$BASE/conf/node$i.hcl" > "$BASE/log/node$i.log" 2>&1 & done
  sleep 15
}

# 修正：端口随节点号变化（上一版写死 8500+1 是 bug）
probe() {
  local n=$1
  curl -s --max-time 4 -o /dev/null -w '%{http_code}' -X PUT -d x \
    "http://127.0.0.$n:$((8500+n))/v1/kv/ops/probe" 2>/dev/null
}

restore
echo "基线 leader: $(consul operator raft list-peers -http-addr=http://127.0.0.1:8501 | awk '$4=="leader"{print $1}')"

echo
echo "########## 场景 1：剩 2 台（多数派）##########"
LNUM=$(consul operator raft list-peers -http-addr=http://127.0.0.1:8501 | awk '$4=="leader"{print $1}' | grep -oE '[0-9]+$')
VICTIM=$([ "$LNUM" != 3 ] && echo 3 || echo 2)
echo "停掉 node$VICTIM"
pkill -f "conf/node$VICTIM.hcl"; sleep 8
for n in 1 2 3; do
  [ "$n" = "$VICTIM" ] && continue
  printf "  node%s 写 HTTP=%s\n" "$n" "$(probe $n)"
done

echo
echo "########## 场景 2：剩 1 台（少数派）##########"
ALIVE=$(pgrep -af 'consul agent' | grep -oE 'node[0-9]\.hcl' | grep -oE '[0-9]' | sort)
KEEP=$(echo "$ALIVE" | head -1)
DROP=$(echo "$ALIVE" | sed -n 2p)
echo "停掉 node$DROP，只留 node$KEEP"
pkill -f "conf/node$DROP.hcl"; sleep 8
echo "  存活进程 = $(pgrep -cf 'consul agent')"
printf "  少数派 node%s 写 HTTP=%s\n" "$KEEP" "$(probe $KEEP)"
R=$(curl -s --max-time 4 "http://127.0.0.$KEEP:$((8500+KEEP))/v1/kv/ops/probe?raw" 2>&1)
echo "  少数派 node$KEEP 读 = [${R:0:55}]"

pkill -f 'consul agent' 2>/dev/null; sleep 1
echo "已清理"
